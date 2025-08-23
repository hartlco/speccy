import AVFoundation
import Combine
import Foundation
import CryptoKit
import MediaPlayer

/// Simple TTS service using AVSpeechSynthesizer with background audio support.
final class SpeechService: NSObject, ObservableObject {
    enum Engine: String, CaseIterable, Identifiable {
        case system
        case openAI
        var id: String { rawValue }
    }
    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case speaking(progress: Double)
        case paused(progress: Double)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentUtterance: AVSpeechUtterance?
    @Published var engine: Engine = .system

    private let synthesizer = AVSpeechSynthesizer()
    private var cancellables = Set<AnyCancellable>()
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private var downloadDestinations: [Int: URL] = [:]
    private var currentDownloadTask: URLSessionDownloadTask?
    private var currentPlaylist: [URL] = []
    private var currentChunkIndex: Int = 0
    private var chunksTotalCount: Int = 0
    private var pendingDownloads: [(text: String, destination: URL)] = []
    private var downloadedChunksCount: Int = 0
    private var currentDownloadExpectedBytes: Int64 = 0
    private var currentDownloadWrittenBytes: Int64 = 0

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        setupRemoteCommandCenter()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleAudioSessionInterruption(note)
        }
        // Load persisted engine selection
        if let saved = UserDefaults.standard.string(forKey: Self.engineDefaultsKey), let parsed = Engine(rawValue: saved) {
            engine = parsed
        }
        // Persist engine changes
        $engine
            .sink { value in
                UserDefaults.standard.set(value.rawValue, forKey: Self.engineDefaultsKey)
            }
            .store(in: &cancellables)
    }

    private static let engineDefaultsKey = "SPEECH_ENGINE"

    @MainActor
    func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothHFP, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        #else
        // macOS does not use AVAudioSession
        #endif
    }

    @MainActor
    func speak(text: String, voiceIdentifier: String? = nil, languageCode: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        stop()
        switch engine {
        case .system:
            let utterance = AVSpeechUtterance(string: text)
            if let voiceIdentifier { utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) }
            else if let languageCode { utterance.voice = AVSpeechSynthesisVoice(language: languageCode) }
            utterance.rate = rate
            utterance.prefersAssistiveTechnologySettings = true
            utterance.postUtteranceDelay = 0.0
            utterance.preUtteranceDelay = 0.0
            currentUtterance = utterance
            synthesizer.speak(utterance)
            state = .speaking(progress: 0)
            log("System TTS started")

        case .openAI:
            // Split long texts into chunks and cache each
            guard let config = loadOpenAIConfig() else {
                print("Missing OPENAI_API_KEY; cannot use OpenAI engine.")
                state = .idle
                return
            }
            let parts = chunkText(text)
            let urls: [URL] = parts.map { part in
                let key = cacheKey(text: part, model: config.model, voice: config.voice, format: config.format)
                return ensureCacheFileURL(forKey: key, format: config.format)
            }
            currentPlaylist = urls
            chunksTotalCount = urls.count
            currentChunkIndex = 0
            // Prepare downloads for missing chunks
            pendingDownloads = zip(parts, urls).filter { (_, url) in !FileManager.default.fileExists(atPath: url.path) }
            downloadedChunksCount = 0
            log("OpenAI chunks: total=\(chunksTotalCount), toDownload=\(pendingDownloads.count)")
            currentDownloadExpectedBytes = 0
            currentDownloadWrittenBytes = 0
            progressTimer?.invalidate()
            progressTimer = nil
            audioPlayer?.stop()
            audioPlayer = nil

            if pendingDownloads.isEmpty {
                // All cached, start playing immediately
                log("All chunks cached. Starting playback.")
                playChunk(at: 0)
            } else {
                // Download sequentially, then play
                state = .downloading(progress: 0)
                startNextDownload(config: config)
            }
        }
    }

    @MainActor
    func pause() {
        switch engine {
        case .system:
            if synthesizer.isSpeaking {
                synthesizer.pauseSpeaking(at: .immediate)
            }
        case .openAI:
            audioPlayer?.pause()
            if case let .speaking(progress) = state {
                state = .paused(progress: progress)
            }
        }
        updateNowPlayingPlayback(isPlaying: false)
        log("Paused")
    }

    @MainActor
    func resume() {
        switch engine {
        case .system:
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
            }
        case .openAI:
            audioPlayer?.play()
            if case let .paused(progress) = state {
                state = .speaking(progress: progress)
            }
        }
        updateNowPlayingPlayback(isPlaying: true)
        log("Resumed")
    }

    @MainActor
    func stop() {
        switch engine {
        case .system:
            if synthesizer.isSpeaking || synthesizer.isPaused {
                synthesizer.stopSpeaking(at: .immediate)
            }
            currentUtterance = nil
            state = .idle

        case .openAI:
            progressTimer?.invalidate()
            progressTimer = nil
            audioPlayer?.stop()
            audioPlayer = nil
            currentDownloadTask?.cancel()
            currentDownloadTask = nil
            pendingDownloads.removeAll()
            currentPlaylist.removeAll()
            chunksTotalCount = 0
            currentChunkIndex = 0
            downloadDestinations.removeAll()
            state = .idle
        }
        clearNowPlaying()
        log("Stopped")
    }

    @MainActor
    private func playLocalFile(url: URL) {
        progressTimer?.invalidate()
        progressTimer = nil
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            guard let player = audioPlayer else { return }
            player.prepareToPlay()
            player.delegate = self
            player.play()
            state = .speaking(progress: 0)
            startProgressTimer(player: player)
            updateNowPlayingInfo(duration: player.duration, elapsed: player.currentTime, isPlaying: true)
            log("Playing chunk \(currentChunkIndex + 1)/\(max(chunksTotalCount, 1))")
        } catch {
            print("Failed to play cached audio: \(error)")
            state = .idle
            log("Error: Failed to play audio: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func startProgressTimer(player: AVAudioPlayer) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard player.duration > 0 else { return }
            let chunkFraction = min(max(player.currentTime / player.duration, 0), 1)
            let total = max(self.chunksTotalCount, 1)
            let combined = (Double(self.currentChunkIndex) + chunkFraction) / Double(total)
            switch self.state {
            case .speaking:
                self.state = .speaking(progress: combined)
            case .paused:
                self.state = .paused(progress: combined)
            case .downloading, .idle:
                self.state = .speaking(progress: combined)
            }
            self.updateNowPlayingElapsed(elapsed: player.currentTime, duration: player.duration, isPlaying: player.isPlaying)
        }
        RunLoop.main.add(progressTimer!, forMode: .common)
    }

    private struct OpenAIConfig {
        let apiKey: String
        let model: String
        let voice: String
        let format: String
    }

    private func loadOpenAIConfig() -> OpenAIConfig? {
        // Priority: UserDefaults -> Info.plist -> env var
        let defaultsKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY")
        let infoKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String
        let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        guard let apiKey = defaultsKey ?? infoKey ?? envKey, !apiKey.isEmpty else {
            print("Missing OPENAI_API_KEY. Set in UserDefaults, Info.plist, or environment.")
            return nil
        }
        // Reasonable defaults
        let model = UserDefaults.standard.string(forKey: "OPENAI_TTS_MODEL") ?? "gpt-4o-mini-tts"
        let voice = UserDefaults.standard.string(forKey: "OPENAI_TTS_VOICE") ?? "alloy"
        let format = UserDefaults.standard.string(forKey: "OPENAI_TTS_FORMAT") ?? "mp3"
        return OpenAIConfig(apiKey: apiKey, model: model, voice: voice, format: format)
    }

    private func downloadOpenAIAudio(text: String, config: OpenAIConfig, destination: URL) {
        struct Payload: Encodable { let model: String; let voice: String; let input: String; let format: String }
        let payload = Payload(model: config.model, voice: config.voice, input: text, format: config.format)
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            print("Failed to encode payload: \(error)")
            state = .idle
            log("Error: Failed to encode request: \(error.localizedDescription)")
            return
        }
        currentDownloadExpectedBytes = 0
        currentDownloadWrittenBytes = 0
        state = .downloading(progress: 0)
        let task = urlSession.downloadTask(with: request)
        currentDownloadTask = task
        downloadDestinations[task.taskIdentifier] = destination
        log("Downloading chunk \(downloadedChunksCount + 1)/\(max(chunksTotalCount, 1))…")
        task.resume()
    }

    private func cacheKey(text: String, model: String, voice: String, format: String) -> String {
        let combined = [model, voice, format, text].joined(separator: "|")
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("tts-cache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func ensureCacheFileURL(forKey key: String, format: String) -> URL {
        return cacheDirectory().appendingPathComponent("\(key).\(format)")
    }

    // MARK: - Chunking & sequential download

    private func chunkText(_ text: String, maxChunkLength: Int = 3800) -> [String] {
        guard text.count > maxChunkLength else { return [text] }
        var result: [String] = []
        var current = ""
        let separators = CharacterSet(charactersIn: ".!?\n\t")
        let tokens = text.split(maxSplits: Int.max, omittingEmptySubsequences: false, whereSeparator: { char in
            char.unicodeScalars.contains { separators.contains($0) }
        })
        for token in tokens {
            let piece = String(token)
            if current.count + piece.count + 1 > maxChunkLength {
                if !current.isEmpty { result.append(current) }
                current = piece
            } else {
                current += piece
            }
        }
        if !current.isEmpty { result.append(current) }
        // Fallback safety: ensure no empty chunks
        return result.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func startNextDownload(config: OpenAIConfig) {
        guard !pendingDownloads.isEmpty else {
            // All downloaded; start playback
            playChunk(at: 0)
            return
        }
        let next = pendingDownloads.removeFirst()
        downloadOpenAIAudio(text: next.text, config: config, destination: next.destination)
    }

    private func playChunk(at index: Int) {
        guard currentPlaylist.indices.contains(index) else {
            state = .idle
            log("Playback completed")
            return
        }
        currentChunkIndex = index
        playLocalFile(url: currentPlaylist[index])
    }

    // MARK: - Logging
    @Published var logs: [String] = []
    private func log(_ message: String) {
        let entry = message
        logs.append(entry)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }

    // MARK: - Interruption handling
    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            log("Audio session interrupted (began)")
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            let shouldResume = optionsValue.map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            log("Audio session interruption ended. shouldResume=\(shouldResume)")
            if shouldResume {
                Task { @MainActor in
                    do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
                    self.resume()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Now Playing & Remote Controls

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            switch self.state {
            case .idle: self.speak(text: self.currentUtterance?.speechString ?? "")
            case .speaking: self.pause()
            case .paused: self.resume()
            case .downloading: break
            }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            self.playChunk(at: self.currentChunkIndex + 1)
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            let prev = max(self.currentChunkIndex - 1, 0)
            self.playChunk(at: prev)
            return .success
        }
    }

    private func updateNowPlayingInfo(duration: TimeInterval, elapsed: TimeInterval, isPlaying: Bool) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = "Speccy"
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private var currentPlayerElapsed: TimeInterval {
        audioPlayer?.currentTime ?? 0
    }
    private var currentPlayerDuration: TimeInterval {
        audioPlayer?.duration ?? 1
    }

    private func updateNowPlayingElapsed(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlayback(isPlaying: Bool) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

@MainActor
extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        state = .speaking(progress: 0)
        updateNowPlayingInfo(duration: 1, elapsed: 0, isPlaying: true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        state = .idle
        clearNowPlaying()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        state = .idle
        clearNowPlaying()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        if case let .speaking(progress) = state { state = .paused(progress: progress) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        if case let .paused(progress) = state { state = .speaking(progress: progress) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let total = utterance.speechString.count
        guard total > 0 else { return }
        let progress = Double(characterRange.location + characterRange.length) / Double(total)
        switch state {
        case .speaking:
            state = .speaking(progress: progress)
        case .paused:
            state = .paused(progress: progress)
        case .downloading:
            break
        case .idle:
            break
        }
        updateNowPlayingElapsed(elapsed: progress, duration: 1, isPlaying: true)
    }
}

@MainActor
extension SpeechService: URLSessionDownloadDelegate, AVAudioPlayerDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        currentDownloadExpectedBytes = totalBytesExpectedToWrite
        currentDownloadWrittenBytes = totalBytesWritten
        let chunksCompleted = Double(downloadedChunksCount)
        let chunksTotal = max(Double(chunksTotalCount), 1)
        let intra = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        let overall = min((chunksCompleted + intra) / chunksTotal, 0.999)
        state = .downloading(progress: overall)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination = downloadDestinations[downloadTask.taskIdentifier] else {
            print("No destination for downloaded file (task \(downloadTask.taskIdentifier))")
            log("Error: Missing destination for task \(downloadTask.taskIdentifier)")
            state = .idle
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            downloadedChunksCount += 1
            // If all downloads complete, start playback; otherwise continue downloading next
            if downloadedChunksCount >= chunksTotalCount || pendingDownloads.isEmpty {
                playChunk(at: 0)
            } else if let config = loadOpenAIConfig() {
                startNextDownload(config: config)
            }
        } catch {
            print("Failed moving downloaded audio: \(error)")
            state = .idle
            log("Error: Failed moving download: \(error.localizedDescription)")
        }
        downloadDestinations.removeValue(forKey: downloadTask.taskIdentifier)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("Download failed: \(error)")
            state = .idle
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Move to next chunk if available
        let nextIndex = currentChunkIndex + 1
        if currentPlaylist.indices.contains(nextIndex) {
            playChunk(at: nextIndex)
        } else {
            progressTimer?.invalidate()
            progressTimer = nil
            state = .idle
        }
    }
}
