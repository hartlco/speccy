import AVFoundation
import Combine
import Foundation
import CryptoKit
import MediaPlayer
import SwiftData

/// TTS service using backend API instead of direct OpenAI calls and iCloud sync.
@MainActor
final class SpeechServiceBackend: NSObject, ObservableObject {
    static let shared = SpeechServiceBackend()
    
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
    
    private var currentPlaylist: [URL] = []
    private var currentChunkIndex: Int = 0
    private var chunksTotalCount: Int = 0
    private var downloadedChunksCount: Int = 0
    private var nowPlayingTitle: String?
    private var currentResumeKey: String?
    private var currentTextHash: String?
    private var pendingSeekTime: TimeInterval?
    private var initialChunkIndex: Int?
    private var chunkDurations: [TimeInterval] = []
    private var currentPlaybackRate: Float = 1.0
    private var modelContext: ModelContext?
    
    // Backend service
    private let backendService = TTSBackendService.shared
    
    private override init() {
        super.init()
        configureAudioSession()
        setupRemoteCommandCenter()
        #if os(iOS) || os(tvOS) || os(watchOS)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                self?.handleAudioSessionInterruption(note)
            }
        }
        #endif
    }

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
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
        
        Task {
            await preloadAudioWithBackend(text: text, config: config, onProgress: onProgress, onCompletion: onCompletion)
        }
    }
    
    private func preloadAudioWithBackend(text: String, config: OpenAIConfig, onProgress: @escaping (Double) -> Void, onCompletion: @escaping (Result<Void, Error>) -> Void) async {
        do {
            // Authenticate with backend first
            let authResponse = try await backendService.authenticate(openAIToken: config.apiKey)
            AppLogger.shared.info("Authenticated with backend for user: \(authResponse.user_id ?? "unknown")", category: .system)
        } catch {
            AppLogger.shared.error("Failed to authenticate with backend: \(error)", category: .system)
            onCompletion(.failure(error))
            return
        }
        
        let parts = chunkText(text)
        let urls: [URL] = parts.map { part in
            let key = cacheKey(text: part, model: config.model, voice: config.voice, format: config.format)
            return ensureCacheFileURL(forKey: key, format: config.format)
        }
        
        // Check which chunks are already cached locally
        var missingChunks: [(String, URL)] = []
        var completedChunks = 0
        
        for (part, url) in zip(parts, urls) {
            if FileManager.default.fileExists(atPath: url.path) {
                completedChunks += 1
            } else {
                missingChunks.append((part, url))
            }
            
            let progress = Double(completedChunks) / Double(parts.count)
            onProgress(progress)
        }
        
        if missingChunks.isEmpty {
            onProgress(1.0)
            onCompletion(.success(()))
            return
        }
        
        // Download missing chunks from backend
        await downloadChunksFromBackend(missingChunks: missingChunks, config: config, totalChunks: parts.count, onProgress: onProgress, onCompletion: onCompletion)
    }
    
    private func downloadChunksFromBackend(missingChunks: [(String, URL)], config: OpenAIConfig, totalChunks: Int, onProgress: @escaping (Double) -> Void, onCompletion: @escaping (Result<Void, Error>) -> Void) async {
        var remainingChunks = missingChunks
        var completedChunks = totalChunks - missingChunks.count
        
        for (text, destination) in remainingChunks {
            do {
                // Generate TTS via backend
                let ttsResponse = try await backendService.generateTTS(
                    text: text,
                    voice: config.voice,
                    model: config.model,
                    format: config.format,
                    speed: 1.0, // TODO: Make configurable
                    openAIToken: config.apiKey
                )
                
                guard let fileId = ttsResponse.file_id, let status = ttsResponse.status else {
                    throw TTSBackendError.ttsGenerationFailed("Invalid response from backend")
                }
                
                if status == "ready" {
                    // File is ready, download it
                    let localURL = try await backendService.downloadFile(fileId: fileId)
                    
                    // Move to our cache location
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: localURL, to: destination)
                    
                    completedChunks += 1
                    let progress = Double(completedChunks) / Double(totalChunks)
                    onProgress(progress)
                    
                } else if status == "generating" {
                    // Wait for generation to complete
                    guard let contentHash = ttsResponse.content_hash else {
                        throw TTSBackendError.ttsGenerationFailed("Missing content hash")
                    }
                    
                    // Poll for completion
                    let maxPolls = 30 // Max 30 seconds
                    for _ in 0..<maxPolls {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                        
                        let statusResponse = try await backendService.getFileStatus(contentHash: contentHash)
                        
                        if statusResponse.status == "ready", let fileId = statusResponse.file_id {
                            let localURL = try await backendService.downloadFile(fileId: fileId)
                            
                            try? FileManager.default.removeItem(at: destination)
                            try FileManager.default.moveItem(at: localURL, to: destination)
                            
                            completedChunks += 1
                            let progress = Double(completedChunks) / Double(totalChunks)
                            onProgress(progress)
                            break
                            
                        } else if statusResponse.status == "failed" {
                            throw TTSBackendError.ttsGenerationFailed("Backend generation failed")
                        }
                        // Continue polling if still generating
                    }
                } else if status == "failed" {
                    throw TTSBackendError.ttsGenerationFailed("Backend generation failed")
                }
                
            } catch {
                AppLogger.shared.error("Failed to download chunk from backend: \(error)", category: .system)
                onCompletion(.failure(error))
                return
            }
        }
        
        onProgress(1.0)
        onCompletion(.success(()))
    }

    @MainActor
    func speak(text: String, title: String? = nil, resumeKey: String? = nil, voiceIdentifier: String? = nil, languageCode: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        stop()
        nowPlayingTitle = title
        currentResumeKey = resumeKey
        
        currentPlaybackRate = rate
        
        let textHash = sha256(text)
        currentTextHash = textHash
        let saved = resumeKey.flatMap { loadProgress(forKey: $0) }
        
        guard let config = loadOpenAIConfig() else {
            AppLogger.shared.error("OpenAI API key not found", category: .system)
            return
        }
        
        let parts = chunkText(text)
        chunksTotalCount = parts.count
        currentChunkIndex = saved?.chunkIndex ?? 0
        initialChunkIndex = currentChunkIndex
        
        let urls: [URL] = parts.map { part in
            let key = cacheKey(text: part, model: config.model, voice: config.voice, format: config.format)
            return ensureCacheFileURL(forKey: key, format: config.format)
        }
        
        currentPlaylist = urls
        
        if saved?.seekTime ?? 0 > 0 {
            pendingSeekTime = saved?.seekTime
        }
        
        preloadAudio(text: text, onProgress: { [weak self] progress in
            DispatchQueue.main.async {
                self?.state = .downloading(progress: progress)
            }
        }, onCompletion: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.playCurrentChunk()
                case .failure(let error):
                    AppLogger.shared.error("Failed to preload audio: \(error)", category: .system)
                    self?.state = .idle
                }
            }
        })
    }

    @MainActor
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        state = .idle
        currentPlaylist = []
        currentChunkIndex = 0
        chunksTotalCount = 0
        downloadedChunksCount = 0
        pendingSeekTime = nil
        initialChunkIndex = nil
        chunkDurations = []
    }

    @MainActor
    func pause() {
        guard case .speaking(let progress) = state else { return }
        audioPlayer?.pause()
        progressTimer?.invalidate()
        progressTimer = nil
        state = .paused(progress: progress)
    }

    @MainActor
    func resume() {
        guard case .paused(let progress) = state else { return }
        audioPlayer?.play()
        startProgressTimer()
        state = .speaking(progress: progress)
    }

    @MainActor
    func playCurrentChunk() {
        guard currentChunkIndex < currentPlaylist.count else {
            stop()
            return
        }
        
        let url = currentPlaylist[currentChunkIndex]
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.rate = currentPlaybackRate
            audioPlayer?.prepareToPlay()
            
            if let seekTime = pendingSeekTime {
                audioPlayer?.currentTime = seekTime
                pendingSeekTime = nil
            }
            
            audioPlayer?.play()
            state = .speaking(progress: calculateOverallProgress())
            startProgressTimer()
            updateNowPlayingInfo()
            
        } catch {
            AppLogger.shared.error("Failed to play audio chunk: \(error)", category: .playback)
            playNextChunk()
        }
    }

    @MainActor
    private func playNextChunk() {
        currentChunkIndex += 1
        playCurrentChunk()
    }

    private func calculateOverallProgress() -> Double {
        guard chunksTotalCount > 0 else { return 0 }
        
        let chunkProgress = Double(currentChunkIndex) / Double(chunksTotalCount)
        let currentChunkProgress = (audioPlayer?.currentTime ?? 0) / (audioPlayer?.duration ?? 1)
        let intraChunkProgress = currentChunkProgress / Double(chunksTotalCount)
        
        return chunkProgress + intraChunkProgress
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    @MainActor
    private func updateProgress() {
        let progress = calculateOverallProgress()
        state = .speaking(progress: progress)
        updateNowPlayingInfo()
        
        if let resumeKey = currentResumeKey {
            saveProgress(forKey: resumeKey, chunkIndex: currentChunkIndex, seekTime: audioPlayer?.currentTime ?? 0)
        }
    }

    // MARK: - Helper Methods (keeping existing implementations)
    
    private func chunkText(_ text: String) -> [String] {
        // Keep existing chunking logic
        let maxChunkLength = 3000
        var chunks: [String] = []
        var currentChunk = ""
        
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            if currentChunk.count + trimmed.count + 1 <= maxChunkLength {
                if !currentChunk.isEmpty {
                    currentChunk += ". "
                }
                currentChunk += trimmed
            } else {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk + ".")
                }
                currentChunk = trimmed
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk + ".")
        }
        
        return chunks.isEmpty ? [text] : chunks
    }
    
    private func cacheKey(text: String, model: String, voice: String, format: String) -> String {
        let combined = "\(text)|\(model)|\(voice)|\(format)"
        return sha256(combined)
    }
    
    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func ensureCacheFileURL(forKey key: String, format: String) -> URL {
        let cacheDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TTSCache", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        return cacheDir.appendingPathComponent("\(key).\(format)")
    }
    
    private func loadOpenAIConfig() -> OpenAIConfig? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let apiKey = plist["OPENAI_API_KEY"] as? String else {
            return nil
        }
        
        return OpenAIConfig(
            apiKey: apiKey,
            model: plist["OPENAI_MODEL"] as? String ?? "tts-1",
            voice: plist["OPENAI_VOICE"] as? String ?? "nova",
            format: plist["OPENAI_FORMAT"] as? String ?? "mp3"
        )
    }
    
    private func saveProgress(forKey key: String, chunkIndex: Int, seekTime: TimeInterval) {
        let progress = PlaybackProgress(chunkIndex: chunkIndex, seekTime: seekTime)
        let data = try? JSONEncoder().encode(progress)
        UserDefaults.standard.set(data, forKey: "playback_progress_\(key)")
    }
    
    private func loadProgress(forKey key: String) -> PlaybackProgress? {
        guard let data = UserDefaults.standard.data(forKey: "playback_progress_\(key)"),
              let progress = try? JSONDecoder().decode(PlaybackProgress.self, from: data) else {
            return nil
        }
        return progress
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.resume()
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }
        
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = nowPlayingTitle ?? "TTS Playback"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer?.currentTime ?? 0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = audioPlayer?.duration ?? 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = audioPlayer?.isPlaying == true ? currentPlaybackRate : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    // MARK: - Missing Methods for Compatibility

    func isAudioCached(for text: String) -> Bool {
        guard let config = loadOpenAIConfig() else { return false }
        
        let parts = chunkText(text)
        let urls: [URL] = parts.map { part in
            let key = cacheKey(text: part, model: config.model, voice: config.voice, format: config.format)
            return ensureCacheFileURL(forKey: key, format: config.format)
        }
        
        return urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    func isAudioAvailableInSync(for text: String) async -> Bool {
        // Since we're using backend service now, we don't have sync availability
        // Just return whether it's cached locally
        return isAudioCached(for: text)
    }

    func seek(toFraction fraction: Double, fullText: String, languageCode: String?, rate: Float) {
        guard let player = audioPlayer else { return }
        let seekTime = fraction * player.duration
        player.currentTime = seekTime
        updateNowPlayingInfo()
    }

    func setPlaybackRate(_ rate: Float) {
        currentPlaybackRate = rate
        audioPlayer?.rate = rate
    }

    func nextChunk() {
        if currentChunkIndex < currentPlaylist.count - 1 {
            currentChunkIndex += 1
            playCurrentChunk()
        }
    }

    func previousChunk() {
        if currentChunkIndex > 0 {
            currentChunkIndex -= 1
            playCurrentChunk()
        }
    }

    var currentPlayerDuration: TimeInterval {
        return audioPlayer?.duration ?? 0
    }

    var currentPlayerElapsed: TimeInterval {
        return audioPlayer?.currentTime ?? 0
    }

    // Public utility methods needed by other parts of the app
    func getOpenAIConfig() -> OpenAIConfig? {
        return loadOpenAIConfig()
    }
    
    func generateCacheKey(text: String, model: String, voice: String, format: String) -> String {
        return cacheKey(text: text, model: model, voice: voice, format: format)
    }
    
    func getCacheFileURL(forKey key: String, format: String) -> URL {
        return ensureCacheFileURL(forKey: key, format: format)
    }
    
    func splitTextIntoChunks(_ text: String) -> [String] {
        return chunkText(text)
    }
    
    #if os(iOS) || os(tvOS) || os(watchOS)
    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }
    #endif
}

// MARK: - AVAudioPlayerDelegate

extension SpeechServiceBackend: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if flag {
                playNextChunk()
            } else {
                stop()
            }
        }
    }
}

// MARK: - Supporting Types

struct OpenAIConfig {
    let apiKey: String
    let model: String
    let voice: String
    let format: String
}

private struct PlaybackProgress: Codable {
    let chunkIndex: Int
    let seekTime: TimeInterval
}