import AVFoundation
import Combine
import Foundation
import CryptoKit

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
    private var currentDownloadDestination: URL?
    private var currentDownloadTask: URLSessionDownloadTask?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
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

        case .openAI:
            // Look up from cache first, else download and cache
            guard let config = loadOpenAIConfig() else {
                print("Missing OPENAI_API_KEY; cannot use OpenAI engine.")
                state = .idle
                return
            }
            let key = cacheKey(text: text, model: config.model, voice: config.voice, format: config.format)
            let fileURL = ensureCacheFileURL(forKey: key, format: config.format)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                playLocalFile(url: fileURL)
            } else {
                downloadOpenAIAudio(text: text, config: config, destination: fileURL)
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
            state = .idle
        }
    }

    @MainActor
    private func playLocalFile(url: URL) {
        progressTimer?.invalidate()
        progressTimer = nil
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            guard let player = audioPlayer else { return }
            player.prepareToPlay()
            player.play()
            startProgressTimer(player: player)
        } catch {
            print("Failed to play cached audio: \(error)")
            state = .idle
        }
    }

    @MainActor
    private func startProgressTimer(player: AVAudioPlayer) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard player.duration > 0 else { return }
            let progress = min(max(player.currentTime / player.duration, 0), 1)
            switch self.state {
            case .speaking:
                self.state = .speaking(progress: progress)
            case .paused:
                self.state = .paused(progress: progress)
            case .downloading:
                break
            case .idle:
                break
            }
            if progress >= 1 || !player.isPlaying {
                self.progressTimer?.invalidate()
                self.progressTimer = nil
                self.state = .idle
            }
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
            return
        }
        currentDownloadDestination = destination
        state = .downloading(progress: 0)
        let task = urlSession.downloadTask(with: request)
        currentDownloadTask = task
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
}

@MainActor
extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        state = .speaking(progress: 0)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        state = .idle
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        state = .idle
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
    }
}

@MainActor
extension SpeechService: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        state = .downloading(progress: progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination = currentDownloadDestination else {
            print("No destination for downloaded file")
            state = .idle
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            playLocalFile(url: destination)
        } catch {
            print("Failed moving downloaded audio: \(error)")
            state = .idle
        }
        currentDownloadDestination = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("Download failed: \(error)")
            state = .idle
        }
    }
}
