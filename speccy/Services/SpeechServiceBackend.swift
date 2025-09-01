import AVFoundation
import Combine
import Foundation
import CryptoKit
import MediaPlayer
import SwiftData

/// TTS service using backend API instead of direct OpenAI calls.
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
        
        AppLogger.shared.info("Starting preload for text of length: \(text.count) characters", category: .system)
        
        Task {
            await preloadAudioWithBackend(text: text, config: config, onProgress: onProgress, onCompletion: onCompletion)
        }
    }
    
    private func preloadAudioWithBackend(text: String, config: OpenAIConfig, onProgress: @escaping (Double) -> Void, onCompletion: @escaping (Result<Void, Error>) -> Void) async {
        do {
            // Authenticate with backend first
            let authResponse = try await backendService.authenticate(openAIToken: config.apiKey)
            AppLogger.shared.info("Authenticated with backend for user: \(authResponse.user_id ?? "unknown")", category: .system)
            
            // Trigger initial sync after authentication (with a small delay to ensure auth is fully complete)
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            await DocumentStateManager.shared.performInitialSync()
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
        // Store generation requests for async polling
        var pendingGenerations: [(contentHash: String, destination: URL)] = []
        var completedChunks = totalChunks - missingChunks.count
        
        // First, initiate all TTS generations without waiting
        for (text, destination) in missingChunks {
            do {
                // Generate TTS via backend (returns immediately)
                let ttsResponse = try await backendService.generateTTS(
                    text: text,
                    voice: config.voice,
                    model: config.model,
                    format: config.format,
                    speed: 1.0, // TODO: Make configurable
                    openAIToken: config.apiKey
                )
                
                guard let status = ttsResponse.status else {
                    throw TTSBackendError.ttsGenerationFailed("Invalid response from backend")
                }
                
                if status == "ready" {
                    // File is already ready, download immediately
                    guard let fileId = ttsResponse.file_id else {
                        throw TTSBackendError.ttsGenerationFailed("Missing file ID for ready file")
                    }
                    
                    let localURL = try await backendService.downloadFile(fileId: fileId)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: localURL, to: destination)
                    
                    completedChunks += 1
                    let progress = Double(completedChunks) / Double(totalChunks)
                    onProgress(progress)
                    
                } else if status == "generating" {
                    // Add to pending list for polling
                    guard let contentHash = ttsResponse.content_hash else {
                        throw TTSBackendError.ttsGenerationFailed("Missing content hash")
                    }
                    pendingGenerations.append((contentHash: contentHash, destination: destination))
                    
                } else if status == "failed" {
                    throw TTSBackendError.ttsGenerationFailed("Backend generation failed immediately")
                }
                
            } catch {
                AppLogger.shared.error("Failed to initiate TTS generation: \(error)", category: .system)
                onCompletion(.failure(error))
                return
            }
        }
        
        // If all chunks are already ready, complete immediately
        if pendingGenerations.isEmpty {
            onProgress(1.0)
            onCompletion(.success(()))
            return
        }
        
        // Poll for pending generations with extended timeout for large texts
        await pollPendingGenerations(
            pending: pendingGenerations,
            completedChunks: &completedChunks,
            totalChunks: totalChunks,
            onProgress: onProgress,
            onCompletion: onCompletion
        )
    }
    
    private func pollPendingGenerations(
        pending: [(contentHash: String, destination: URL)],
        completedChunks: inout Int,
        totalChunks: Int,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<Void, Error>) -> Void
    ) async {
        var remainingGenerations = pending
        let maxPolls = 600 // Max 10 minutes (600 * 1 second)
        let pollInterval: UInt64 = 1_000_000_000 // 1 second
        
        for pollCount in 0..<maxPolls {
            guard !remainingGenerations.isEmpty else {
                // All generations completed
                onProgress(1.0)
                onCompletion(.success(()))
                return
            }
            
            // Check status of all pending generations
            var stillPending: [(contentHash: String, destination: URL)] = []
            
            for (contentHash, destination) in remainingGenerations {
                do {
                    let statusResponse = try await backendService.getFileStatus(contentHash: contentHash)
                    
                    if statusResponse.status == "ready", let fileId = statusResponse.file_id {
                        // Generation complete, download file
                        let localURL = try await backendService.downloadFile(fileId: fileId)
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: localURL, to: destination)
                        
                        completedChunks += 1
                        let progress = Double(completedChunks) / Double(totalChunks)
                        onProgress(progress)
                        
                    } else if statusResponse.status == "failed" {
                        AppLogger.shared.error("Backend generation failed for hash: \(contentHash)", category: .system)
                        onCompletion(.failure(TTSBackendError.ttsGenerationFailed("Backend generation failed")))
                        return
                        
                    } else {
                        // Still generating, keep polling
                        stillPending.append((contentHash: contentHash, destination: destination))
                    }
                    
                } catch {
                    AppLogger.shared.error("Error checking generation status: \(error)", category: .system)
                    stillPending.append((contentHash: contentHash, destination: destination)) // Keep trying
                }
            }
            
            remainingGenerations = stillPending
            
            // Wait before next poll (unless this is the last iteration)
            if pollCount < maxPolls - 1 && !remainingGenerations.isEmpty {
                try? await Task.sleep(nanoseconds: pollInterval)
            }
        }
        
        // Timeout reached
        if !remainingGenerations.isEmpty {
            let errorMessage = "Timeout waiting for TTS generation (\(remainingGenerations.count) chunks still pending)"
            AppLogger.shared.error(errorMessage, category: .system)
            onCompletion(.failure(TTSBackendError.ttsGenerationFailed(errorMessage)))
        }
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
        // Updated chunking logic for larger texts - let backend handle the chunking
        // We'll use larger chunks since backend can handle them better now
        let maxChunkLength = 8000 // Larger chunks since backend will re-chunk as needed
        
        if text.count <= maxChunkLength {
            return [text]
        }
        
        var chunks: [String] = []
        var currentChunk = ""
        
        // Split by paragraphs first for better natural breaks
        let paragraphs = text.components(separatedBy: CharacterSet.newlines)
        
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { 
                // Add paragraph break to current chunk if it's not empty
                if !currentChunk.isEmpty {
                    currentChunk += "\n\n"
                }
                continue
            }
            
            if currentChunk.count + trimmed.count + 2 <= maxChunkLength { // +2 for \n\n
                if !currentChunk.isEmpty {
                    currentChunk += "\n\n"
                }
                currentChunk += trimmed
            } else {
                // Current chunk is full, save it and start new chunk
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                }
                
                // If single paragraph is too long, split by sentences
                if trimmed.count > maxChunkLength {
                    let sentences = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                    var sentenceChunk = ""
                    
                    for sentence in sentences {
                        let sentenceTrimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                        if sentenceTrimmed.isEmpty { continue }
                        
                        if sentenceChunk.count + sentenceTrimmed.count + 2 <= maxChunkLength {
                            if !sentenceChunk.isEmpty {
                                sentenceChunk += ". "
                            }
                            sentenceChunk += sentenceTrimmed
                        } else {
                            if !sentenceChunk.isEmpty {
                                chunks.append(sentenceChunk + ".")
                            }
                            sentenceChunk = sentenceTrimmed
                        }
                    }
                    
                    currentChunk = sentenceChunk.isEmpty ? "" : sentenceChunk + "."
                } else {
                    currentChunk = trimmed
                }
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        let resultChunks = chunks.isEmpty ? [text] : chunks
        AppLogger.shared.info("Text chunked into \(resultChunks.count) chunks for backend processing", category: .system)
        return resultChunks
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
        // Priority: UserDefaults -> Info.plist -> env var -> Config.plist
        let defaultsKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY")
        let infoKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String
        let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        
        // Check Config.plist as fallback
        var configPlistKey: String?
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path) {
            configPlistKey = plist["OPENAI_API_KEY"] as? String
        }
        
        guard let apiKey = defaultsKey ?? infoKey ?? envKey ?? configPlistKey, !apiKey.isEmpty else {
            AppLogger.shared.error("Missing OPENAI_API_KEY. Set in UserDefaults, Info.plist, environment, or Config.plist.", category: .system)
            return nil
        }
        
        // Get model/voice/format from UserDefaults or fallback to defaults
        // Migration: Clear invalid model values that aren't supported by backend
        let savedModel = UserDefaults.standard.string(forKey: "OPENAI_TTS_MODEL")
        if let savedModel = savedModel, !["tts-1", "tts-1-hd"].contains(savedModel) {
            UserDefaults.standard.removeObject(forKey: "OPENAI_TTS_MODEL")
        }
        
        let model = UserDefaults.standard.string(forKey: "OPENAI_TTS_MODEL") ?? "tts-1"
        let voice = UserDefaults.standard.string(forKey: "OPENAI_TTS_VOICE") ?? "alloy"
        let format = UserDefaults.standard.string(forKey: "OPENAI_TTS_FORMAT") ?? "mp3"
        
        return OpenAIConfig(
            apiKey: apiKey,
            model: model,
            voice: voice,
            format: format
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