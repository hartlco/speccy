import SwiftUI

struct SpeechPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
    @ObservedObject private var preferences = UserPreferences.shared

    let text: String
    var title: String? = nil
    var languageCode: String? = nil
    var resumeKey: String? = nil
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            // Scrubber (seek only on release)
            Slider(value: $scrubValue, in: 0...1, onEditingChanged: { editing in
                isScrubbing = editing
                if !editing {
                    speech.seek(toFraction: scrubValue, fullText: text, languageCode: languageCode, rate: utteranceRate)
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
            // Always attempt to play; service will use cache for OpenAI
            scrubValue = progress
            speech.setPlaybackRate(preferences.playbackSpeed)
            speech.speak(text: text, title: title, resumeKey: resumeKey, languageCode: languageCode, rate: utteranceRate)
        }
        .onDisappear { speech.stop() }
        .onChange(of: speech.state) { _, _ in if !isScrubbing { scrubValue = progress } }

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
        switch speech.state {
        case .idle: 0
        case .downloading(let value): value
        case .speaking(let value): value
        case .paused(let value): value
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

    private func stop() {
        speech.stop()
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
