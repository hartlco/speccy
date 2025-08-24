import SwiftUI

struct SpeechPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
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
        VStack(spacing: 24) {
            // Scrubber (seek only on release)
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
            Text(progressLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !speech.logs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(speech.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.1fx", Double(preferences.playbackSpeed)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
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
            .padding(.horizontal)

            HStack(spacing: 24) {
                Button(action: toggle) {
                    Image(systemName: playPauseIcon)
                        .font(.system(size: 28, weight: .bold))
                }
                Button(role: .destructive, action: stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 24, weight: .bold))
                }
            }
            .padding(.top, 8)
            Text(previewText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
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
        switch speech.state {
        case .idle, .paused: "play.fill"
        case .downloading: "pause.fill"
        case .speaking: "pause.fill"
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
        return 0.5 // Default speech rate
    }

    private var progressLabel: String {
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
