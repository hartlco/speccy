import Foundation
import SwiftUI
import Combine

@MainActor
class PlaybackManager: ObservableObject {
    static let shared = PlaybackManager()
    
    struct PlaybackSession {
        let documentId: String
        let title: String
        let text: String
        let languageCode: String?
        let resumeKey: String
    }
    
    @Published private(set) var currentSession: PlaybackSession?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var currentTitle: String = ""
    
    private var speechService: SpeechServiceBackend?
    private var progressCancellable: AnyCancellable?
    private var speedChangeCancellable: AnyCancellable?
    private let backendService = TTSBackendService.shared
    
    private var lastSyncedProgress: Double = 0.0
    private let syncThreshold: Double = 0.05 // Only sync if progress changed by 5%
    
    private init() {
        // Observe playback speed changes and update active speech service
        speedChangeCancellable = UserPreferences.shared.$playbackSpeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSpeed in
                self?.speechService?.setPlaybackRate(newSpeed)
            }
    }
    
    var hasActiveSession: Bool {
        currentSession != nil && (isPlaying || isPaused || isLoading)
    }
    
    var showMiniPlayer: Bool {
        hasActiveSession
    }
    
    func startPlayback(
        documentId: String,
        title: String,
        text: String,
        languageCode: String? = nil,
        resumeKey: String,
        speechService: SpeechServiceBackend
    ) {
        AppLogger.shared.info("Starting playback session for '\(title)'", category: .playback)
        
        // Update session
        currentSession = PlaybackSession(
            documentId: documentId,
            title: title,
            text: text,
            languageCode: languageCode,
            resumeKey: resumeKey
        )
        
        currentTitle = title.isEmpty ? "Untitled" : title
        self.speechService = speechService
        
        // Try to restore playback state from backend
        Task { @MainActor in
            await restorePlaybackStateFromBackend()
        }
        
        // Start monitoring speech service state
        startMonitoring()
        
        // Begin playback
        isLoading = true
        speechService.speak(
            text: text,
            title: title,
            resumeKey: resumeKey,
            languageCode: languageCode,
            rate: UserPreferences.shared.playbackSpeed
        )
    }
    
    func togglePlayback() {
        guard let speechService = speechService else { return }
        
        switch speechService.state {
        case .speaking:
            speechService.pause()
        case .paused:
            speechService.resume()
        case .idle:
            // Restart if we have a session
            if let session = currentSession {
                speechService.speak(
                    text: session.text,
                    title: session.title,
                    resumeKey: session.resumeKey,
                    languageCode: session.languageCode,
                    rate: UserPreferences.shared.playbackSpeed
                )
            }
        case .downloading:
            // Can't control during download
            break
        }
    }
    
    func stopPlayback() {
        AppLogger.shared.info("Stopping playback session", category: .playback)
        
        speechService?.stop()
        stopMonitoring()
        
        currentSession = nil
        isPlaying = false
        isPaused = false
        isLoading = false
        progress = 0.0
        currentTitle = ""
        speechService = nil
    }
    
    func seek(to fraction: Double) {
        guard let session = currentSession,
              let speechService = speechService else { return }
        
        speechService.seek(
            toFraction: fraction,
            fullText: session.text,
            languageCode: session.languageCode,
            rate: UserPreferences.shared.playbackSpeed
        )
    }
    
    func nextChunk() {
        speechService?.nextChunk()
    }
    
    func previousChunk() {
        speechService?.previousChunk()
    }
    
    private func startMonitoring() {
        guard let speechService = speechService else { return }
        
        progressCancellable = speechService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateFromSpeechState(state)
            }
    }
    
    private func stopMonitoring() {
        progressCancellable?.cancel()
        progressCancellable = nil
    }
    
    private func updateFromSpeechState(_ state: SpeechServiceBackend.State) {
        switch state {
        case .idle:
            isPlaying = false
            isPaused = false
            isLoading = false
            progress = 0.0
            
        case .downloading(let downloadProgress):
            isPlaying = false
            isPaused = false
            isLoading = true
            progress = downloadProgress
            
        case .speaking(let playProgress):
            isPlaying = true
            isPaused = false
            isLoading = false
            progress = playProgress
            
        case .paused(let pausedProgress):
            isPlaying = false
            isPaused = true
            isLoading = false
            progress = pausedProgress
        }
        
        // Sync to backend if progress changed significantly or state changed
        if shouldSyncToBackend() {
            Task { @MainActor in
                await syncPlaybackStateToBackend()
            }
        }
    }
    
    private func shouldSyncToBackend() -> Bool {
        // Always sync on state changes (play/pause/loading)
        if isPlaying || isPaused || isLoading {
            // For progress changes, only sync if it changed significantly
            let progressDiff = abs(progress - lastSyncedProgress)
            return progressDiff >= syncThreshold || lastSyncedProgress == 0.0
        }
        return true
    }
    
    private func syncPlaybackStateToBackend() async {
        guard let session = currentSession,
              backendService.isAuthenticated else { return }
        
        do {
            _ = try await backendService.syncPlaybackState(
                documentId: session.documentId,
                title: session.title,
                textContent: session.text,
                languageCode: session.languageCode,
                resumeKey: session.resumeKey,
                progress: progress,
                isPlaying: isPlaying,
                isPaused: isPaused,
                isLoading: isLoading,
                currentTitle: currentTitle
            )
            lastSyncedProgress = progress
            AppLogger.shared.info("Synced playback state to backend for '\(session.title)'", category: .playback)
        } catch {
            AppLogger.shared.error("Failed to sync playback state to backend: \(error)", category: .playback)
        }
    }
    
    private func restorePlaybackStateFromBackend() async {
        guard let session = currentSession,
              backendService.isAuthenticated else { return }
        
        do {
            if let backendState = try await backendService.getPlaybackState(documentId: session.documentId) {
                // Only restore progress if it's significant
                if backendState.progress > 0.1 && backendState.progress != progress {
                    AppLogger.shared.info("Restoring playback state from backend: progress=\(backendState.progress)", category: .playback)
                    
                    // Update our local state to match backend
                    progress = backendState.progress
                    lastSyncedProgress = backendState.progress
                    
                    // If the speech service is ready, seek to the restored position
                    if let speechService = speechService {
                        speechService.seek(
                            toFraction: backendState.progress,
                            fullText: session.text,
                            languageCode: session.languageCode,
                            rate: UserPreferences.shared.playbackSpeed
                        )
                    }
                }
            }
        } catch {
            AppLogger.shared.error("Failed to restore playback state from backend: \(error)", category: .playback)
        }
    }
    
    // MARK: - Convenience Methods
    
    func isCurrentSession(documentId: String) -> Bool {
        currentSession?.documentId == documentId
    }
    
    func openFullPlayer() -> PlaybackSession? {
        return currentSession
    }
}