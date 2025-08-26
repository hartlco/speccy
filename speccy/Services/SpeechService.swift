import AVFoundation
import Combine
import Foundation
import CryptoKit
import MediaPlayer

/// TTS service using OpenAI speech synthesis with background audio support.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case speaking(progress: Double)
        case paused(progress: Double)
    }

    @Published private(set) var state: State = .idle
    private var cancellables = Set<AnyCancellable>()
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.speccy.background-downloads")
        config.waitsForConnectivity = true
        config.isDiscretionary = false // Don't wait for optimal conditions
        config.sessionSendsLaunchEvents = true // Launch app when downloads complete
        // Use main operation queue for delegate callbacks to ensure main-actor updates
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
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
    private var nowPlayingTitle: String?
    private var currentResumeKey: String?
    private var currentTextHash: String?
    private var pendingSeekTime: TimeInterval?
    private var initialChunkIndex: Int?
    private var chunkDurations: [TimeInterval] = []
    private var currentPlaybackRate: Float = 1.0

    override init() {
        super.init()
        configureAudioSession()
        setupRemoteCommandCenter()
        #if os(iOS) || os(tvOS) || os(watchOS)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleAudioSessionInterruption(note)
        }
        #endif
    }

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
    func preloadAudio(text: String, onProgress: @escaping (Double) -> Void, onCompletion: @escaping (Result<Void, Error>) -> Void) {
        guard let config = loadOpenAIConfig() else {
            onCompletion(.failure(NSError(domain: "SpeechService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY"])))
            return
        }
        
        let parts = chunkText(text)
        let urls: [URL] = parts.map { part in
            let key = cacheKey(text: part, model: config.model, voice: config.voice, format: config.format)
            return ensureCacheFileURL(forKey: key, format: config.format)
        }
        
        // Check if all chunks are already cached
        let missingChunks = zip(parts, urls).filter { (_, url) in !FileManager.default.fileExists(atPath: url.path) }
        
        if missingChunks.isEmpty {
            onProgress(1.0)
            onCompletion(.success(()))
            return
        }
        
        // Start downloading missing chunks
        downloadChunksSequentially(missingChunks: missingChunks, config: config, totalChunks: parts.count, onProgress: onProgress, onCompletion: onCompletion)
    }
    
    private func downloadChunksSequentially(missingChunks: [(String, URL)], config: OpenAIConfig, totalChunks: Int, onProgress: @escaping (Double) -> Void, onCompletion: @escaping (Result<Void, Error>) -> Void) {
        guard !missingChunks.isEmpty else {
            onProgress(1.0)
            onCompletion(.success(()))
            return
        }
        
        var remainingChunks = missingChunks
        var completedChunks = totalChunks - missingChunks.count
        
        func downloadNext() {
            guard !remainingChunks.isEmpty else {
                onProgress(1.0)
                onCompletion(.success(()))
                return
            }
            
            let (text, destination) = remainingChunks.removeFirst()
            downloadSingleChunk(text: text, destination: destination, config: config) { result in
                switch result {
                case .success:
                    completedChunks += 1
                    let progress = Double(completedChunks) / Double(totalChunks)
                    onProgress(progress)
                    downloadNext()
                case .failure(let error):
                    onCompletion(.failure(error))
                }
            }
        }
        
        downloadNext()
    }
    
    private var preloadCompletions: [Int: (Result<Void, Error>) -> Void] = [:]
    
    private func downloadSingleChunk(text: String, destination: URL, config: OpenAIConfig, completion: @escaping (Result<Void, Error>) -> Void) {
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
            completion(.failure(error))
            return
        }
        
        // Use the main background session and delegate pattern
        let task = urlSession.downloadTask(with: request)
        
        // Store the completion handler and destination for this task
        preloadCompletions[task.taskIdentifier] = completion
        downloadDestinations[task.taskIdentifier] = destination
        
        task.resume()
    }
    
    func isAudioCached(for text: String) -> Bool {
        guard let config = loadOpenAIConfig() else { return false }
        
        let parts = chunkText(text)
        let urls: [URL] = parts.map { part in
            let key = cacheKey(text: part, model: config.model, voice: config.voice, format: config.format)
            return ensureCacheFileURL(forKey: key, format: config.format)
        }
        
        // Check if all chunks exist
        return urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    @MainActor
    func speak(text: String, title: String? = nil, resumeKey: String? = nil, voiceIdentifier: String? = nil, languageCode: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        stop()
        nowPlayingTitle = title
        currentResumeKey = resumeKey
        
        // Set the playback rate for this session
        currentPlaybackRate = rate
        
        let textHash = sha256(text)
        currentTextHash = textHash
        let saved = resumeKey.flatMap { loadProgress(forKey: $0) }
        let validSaved = (saved?.textHash == textHash) ? saved : nil

        AppLogger.shared.info("Starting speech synthesis for '\(title ?? "Untitled")' at rate \(rate)x", category: .speech)

        // Split long texts into chunks and cache each
        guard let config = loadOpenAIConfig() else {
            AppLogger.shared.error("Missing OPENAI_API_KEY; cannot use OpenAI engine", category: .speech)
            state = .idle
            return
        }
        let parts = chunkText(text)
        AppLogger.shared.info("Text split into \(parts.count) chunks", category: .chunks)
        
        let urls: [URL] = parts.map { part in
            let key = cacheKey(text: part, model: config.model, voice: config.voice, format: config.format)
            return ensureCacheFileURL(forKey: key, format: config.format)
        }
        currentPlaylist = urls
        chunksTotalCount = urls.count
        if let openAIProgress = validSaved?.openAI, urls.indices.contains(openAIProgress.chunkIndex) {
            initialChunkIndex = openAIProgress.chunkIndex
            pendingSeekTime = openAIProgress.elapsed
            currentChunkIndex = openAIProgress.chunkIndex
        } else {
            initialChunkIndex = 0
            currentChunkIndex = 0
            pendingSeekTime = nil
        }
        // Precompute durations for local files if present
        if pendingDownloads.isEmpty {
            computeChunkDurations()
        } else {
            chunkDurations = []
        }
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

        let cachedCount = urls.count - pendingDownloads.count
        AppLogger.shared.info("Cache status: \(cachedCount)/\(urls.count) chunks cached", category: .cache)

        if pendingDownloads.isEmpty {
            // All cached, start playing immediately
            log("All chunks cached. Starting playback.")
            AppLogger.shared.info("All chunks cached. Starting playback", category: .playback)
            playChunk(at: initialChunkIndex ?? 0)
        } else {
            // Download sequentially, then play
            state = .downloading(progress: 0)
            AppLogger.shared.info("Starting download of \(pendingDownloads.count) missing chunks", category: .download)
            startNextDownload(config: config)
        }
    }

    @MainActor
    func pause() {
        audioPlayer?.pause()
        if case let .speaking(progress) = state {
            state = .paused(progress: progress)
        }
        updateNowPlayingPlayback(isPlaying: false)
        log("Paused")
        AppLogger.shared.info("Playback paused", category: .playback)
    }

    @MainActor
    func resume() {
        audioPlayer?.play()
        if case let .paused(progress) = state {
            state = .speaking(progress: progress)
        }
        updateNowPlayingPlayback(isPlaying: true)
        log("Resumed")
        AppLogger.shared.info("Playback resumed", category: .playback)
    }

    @MainActor
    func stop() {
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
        clearNowPlaying()
        log("Stopped")
        AppLogger.shared.info("Playback stopped", category: .playback)
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
            player.enableRate = true
            player.rate = max(0.5, min(currentPlaybackRate, 2.0))
            if let seek = pendingSeekTime { player.currentTime = seek; pendingSeekTime = nil }
            player.play()
            state = .speaking(progress: 0)
            startProgressTimer(player: player)
            updateNowPlayingInfo(duration: player.duration, elapsed: player.currentTime, isPlaying: true)
            log("Playing chunk \(currentChunkIndex + 1)/\(max(chunksTotalCount, 1))")
            AppLogger.shared.info("Playing chunk \(currentChunkIndex + 1)/\(max(chunksTotalCount, 1)) (duration: \(String(format: "%.1f", player.duration))s)", category: .playback)
        } catch {
            print("Failed to play cached audio: \(error)")
            state = .idle
            log("Error: Failed to play audio: \(error.localizedDescription)")
            AppLogger.shared.error("Failed to play chunk: \(error.localizedDescription)", category: .playback)
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
            self.persistOpenAIProgress(elapsed: player.currentTime)
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
            playChunk(at: initialChunkIndex ?? 0)
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
    #if os(iOS) || os(tvOS) || os(watchOS)
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
    #endif

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
            case .idle: break // No way to resume without full text context
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
        info[MPMediaItemPropertyTitle] = nowPlayingTitle ?? "Speccy"
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

    // MARK: - Public controls
    func setPlaybackRate(_ rate: Float) {
        currentPlaybackRate = rate
        if let player = audioPlayer {
            player.enableRate = true
            player.rate = max(0.5, min(rate, 2.0))
        }
    }

    func seek(toFraction fraction: Double, fullText: String, languageCode: String?, rate: Float) {
        let clamped = max(0.0, min(1.0, fraction))
        
        // If we have per-chunk durations, map precisely
        if chunkDurations.count == currentPlaylist.count, chunkDurations.reduce(0,+) > 0 {
            let total = chunkDurations.reduce(0,+)
            var time = clamped * total
            var chunk = 0
            for (i, d) in chunkDurations.enumerated() {
                if time <= d { chunk = i; break }
                time -= d
                chunk = i
            }
            currentChunkIndex = chunk
            pendingSeekTime = max(0, min(time, chunkDurations[chunk]))
            playChunk(at: chunk)
        } else {
            // Fallback: assume equal chunk durations
            let total = max(1, chunksTotalCount)
            let position = clamped * Double(total)
            let chunk = min(total - 1, max(0, Int(floor(position))))
            currentChunkIndex = chunk
            pendingSeekTime = nil
            playChunk(at: chunk)
        }
    }

    // MARK: - Utilities
    private func computeChunkDurations() {
        chunkDurations = currentPlaylist.map { url in
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                let seconds = player.duration
                return seconds.isFinite && seconds > 0 ? seconds : 0
            } catch {
                return 0
            }
        }
    }

    // MARK: - Progress persistence
    private struct ProgressRecord: Codable {
        struct OpenAI: Codable { let chunkIndex: Int; let elapsed: TimeInterval }
        let textHash: String
        let openAI: OpenAI?
    }

    private func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadProgress(forKey key: String) -> ProgressRecord? {
        guard let data = UserDefaults.standard.data(forKey: "progress_\(key)") else { return nil }
        return try? JSONDecoder().decode(ProgressRecord.self, from: data)
    }

    private func saveProgress(_ record: ProgressRecord, forKey key: String) {
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: "progress_\(key)")
        }
    }

    private func clearProgress(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: "progress_\(key)")
    }

    private func persistOpenAIProgress(elapsed: TimeInterval) {
        guard let key = currentResumeKey, let textHash = currentTextHash else { return }
        let record = ProgressRecord(textHash: textHash, openAI: .init(chunkIndex: currentChunkIndex, elapsed: elapsed))
        saveProgress(record, forKey: key)
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
            // Ensure directory exists
            let dir = destination.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            
            // Check if this is a preload download
            if let completion = preloadCompletions[downloadTask.taskIdentifier] {
                // This is a preload download - call completion and clean up
                completion(.success(()))
                preloadCompletions.removeValue(forKey: downloadTask.taskIdentifier)
            } else {
                // This is a regular speech download - continue with existing logic
                downloadedChunksCount += 1
                // If all downloads complete, start playback; otherwise continue downloading next
                if downloadedChunksCount >= chunksTotalCount || pendingDownloads.isEmpty {
                    if chunkDurations.isEmpty { computeChunkDurations() }
                    playChunk(at: initialChunkIndex ?? 0)
                } else if let config = loadOpenAIConfig() {
                    startNextDownload(config: config)
                }
            }
        } catch {
            print("Failed moving downloaded audio: \(error)")
            
            // Handle error for both types of downloads
            if let completion = preloadCompletions[downloadTask.taskIdentifier] {
                completion(.failure(error))
                preloadCompletions.removeValue(forKey: downloadTask.taskIdentifier)
            } else {
                state = .idle
                log("Error: Failed moving download: \(error.localizedDescription)")
            }
        }
        
        downloadDestinations.removeValue(forKey: downloadTask.taskIdentifier)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("Download failed: \(error)")
            
            // Handle error for preload downloads
            if let completion = preloadCompletions[task.taskIdentifier] {
                completion(.failure(error))
                preloadCompletions.removeValue(forKey: task.taskIdentifier)
            } else {
                // Handle error for regular speech downloads
                state = .idle
            }
            
            // Clean up
            downloadDestinations.removeValue(forKey: task.taskIdentifier)
        }
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Call the completion handler to inform the system that background processing is complete
        if let identifier = session.configuration.identifier {
            BackgroundSessionManager.shared.callCompletionHandler(for: identifier)
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
            if let key = currentResumeKey { clearProgress(forKey: key) }
        }
    }
}
