import SwiftUI

struct SpeechPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var speech = SpeechService.shared
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var playbackManager = PlaybackManager.shared

    let text: String
    var title: String? = nil
    var languageCode: String? = nil
    var resumeKey: String? = nil
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0
    @State private var isConnectedToManager: Bool = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title section
            VStack(spacing: 8) {
                Text(title ?? "Untitled Document")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(progressLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Progress section
            VStack(spacing: 12) {
                Slider(value: $scrubValue, in: 0...1, onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        if isConnectedToManager {
                            playbackManager.seek(to: scrubValue)
                        } else {
                            speech.seek(toFraction: scrubValue, fullText: text, languageCode: languageCode, rate: utteranceRate)
                        }
                    }
                })
                .tint(.accentColor)
                
                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    Text(formatTime(totalTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)
            Spacer()
            
            // Speed controls
            VStack(spacing: 16) {
                HStack {
                    Text("Playback Speed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1fx", Double(preferences.playbackSpeed)))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                
                Picker("Speed", selection: $preferences.playbackSpeed) {
                    ForEach(preferences.availablePlaybackSpeeds, id: \.self) { rate in
                        Text(String(format: "%.1fx", Double(rate))).tag(rate)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: preferences.playbackSpeed) { _, newVal in
                    speech.setPlaybackRate(newVal)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            // Control buttons
            HStack(spacing: 40) {
                Button(action: previousChunk) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .disabled(!canNavigateBackward)
                
                Button(action: toggle) {
                    Image(systemName: playPauseIcon)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .scaleEffect(isPlaying ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPlaying)
                
                Button(action: nextChunk) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .disabled(!canNavigateForward)
            }
            .padding(.vertical, 20)
            
            // Secondary controls
            HStack(spacing: 32) {
                Button(role: .destructive, action: stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)
            
            // Preview text
            Text(previewText)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .background(.regularMaterial)
        .onAppear {
            scrubValue = progress
            speech.setPlaybackRate(preferences.playbackSpeed)
            
            // Check if we should connect to an existing playback session
            if let currentSession = playbackManager.currentSession,
               currentSession.resumeKey == resumeKey {
                // Connect to existing session
                isConnectedToManager = true
                AppLogger.shared.info("Connected to existing playback session", category: .playback)
            } else {
                // Start new playback
                speech.speak(text: text, title: title, resumeKey: resumeKey, languageCode: languageCode, rate: utteranceRate)
                
                // Register with playback manager
                if let documentId = resumeKey {
                    playbackManager.startPlayback(
                        documentId: documentId,
                        title: title ?? "Untitled",
                        text: text,
                        languageCode: languageCode,
                        resumeKey: resumeKey ?? "",
                        speechService: speech
                    )
                    isConnectedToManager = true
                }
            }
        }
        .onDisappear { 
            // Only stop if we're not connected to the playback manager
            // (i.e., this was a standalone player session)
            if !isConnectedToManager {
                speech.stop()
            }
        }
        .onChange(of: speech.state) { _, _ in 
            if !isScrubbing { 
                scrubValue = progress 
            } 
        }
        .onChange(of: playbackManager.progress) { _, _ in
            if isConnectedToManager && !isScrubbing {
                scrubValue = progress
            }
        }

        .navigationTitle("Player")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button("Done") { dismiss() }
            }
            #endif
        }
    }

    private var progress: Double {
        if isConnectedToManager {
            return playbackManager.progress
        } else {
            switch speech.state {
            case .idle: return 0
            case .downloading(let value): return value
            case .speaking(let value): return value
            case .paused(let value): return value
            }
        }
    }

    private var playPauseIcon: String {
        if isConnectedToManager {
            if playbackManager.isLoading {
                return "circle.dotted"
            } else if playbackManager.isPlaying {
                return "pause.fill"
            } else {
                return "play.fill"
            }
        } else {
            switch speech.state {
            case .idle, .paused: return "play.fill"
            case .downloading: return "circle.dotted"
            case .speaking: return "pause.fill"
            }
        }
    }

    private func toggle() {
        if isConnectedToManager {
            playbackManager.togglePlayback()
        } else {
            switch speech.state {
            case .idle:
                speech.speak(text: text, title: title, resumeKey: resumeKey, languageCode: languageCode, rate: utteranceRate)
            case .speaking:
                speech.pause()
            case .paused:
                speech.resume()
            case .downloading:
                // no-op; could add cancel in future
                break
            }
        }
    }

    private func stop() {
        if isConnectedToManager {
            playbackManager.stopPlayback()
        } else {
            speech.stop()
        }
    }

    private var previewText: String {
        let sample = text.prefix(200)
        return String(sample)
    }

    private var utteranceRate: Float {
        return preferences.playbackSpeed
    }
    
    private var isPlaying: Bool {
        if isConnectedToManager {
            return playbackManager.isPlaying
        } else {
            switch speech.state {
            case .speaking: return true
            default: return false
            }
        }
    }
    
    private var canNavigateBackward: Bool {
        return true
    }
    
    private var canNavigateForward: Bool {
        return true
    }
    
    private var currentTime: TimeInterval {
        return speech.currentPlayerElapsed
    }
    
    private var totalTime: TimeInterval {
        return speech.currentPlayerDuration
    }
    
    private func previousChunk() {
        if isConnectedToManager {
            playbackManager.previousChunk()
        } else {
            speech.previousChunk()
        }
    }
    
    private func nextChunk() {
        if isConnectedToManager {
            playbackManager.nextChunk()
        } else {
            speech.nextChunk()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var progressLabel: String {
        if isConnectedToManager {
            if playbackManager.isLoading {
                return String(format: "Downloading… %.0f%%", playbackManager.progress * 100)
            } else if playbackManager.isPlaying {
                return "Playing"
            } else if playbackManager.isPaused {
                return "Paused"
            } else {
                return "Ready"
            }
        } else {
            switch speech.state {
            case .idle:
                return "Idle"
            case .downloading(let value):
                return String(format: "Downloading… %.0f%%", value * 100)
            case .speaking:
                return "Playing"
            case .paused:
                return "Paused"
            }
        }
    }
}
