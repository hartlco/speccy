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
    
    private var speechService: SpeechService?
    private var progressCancellable: AnyCancellable?
    private var speedChangeCancellable: AnyCancellable?
    
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
        speechService: SpeechService
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
    
    private func updateFromSpeechState(_ state: SpeechService.State) {
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
    }
    
    // MARK: - Convenience Methods
    
    func isCurrentSession(documentId: String) -> Bool {
        currentSession?.documentId == documentId
    }
    
    func openFullPlayer() -> PlaybackSession? {
        return currentSession
    }
}