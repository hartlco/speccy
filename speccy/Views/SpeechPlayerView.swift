import SwiftUI
import AVFoundation

struct SpeechPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()

    let text: String
    var languageCode: String? = nil
    @State private var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            VStack(spacing: 12) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.1fx", rateScale))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(rate) },
                    set: { rate = Float($0) }
                ), in: rateRange.lowerBound...rateRange.upperBound, step: 0.05)
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
        .onAppear { if case .idle = speech.state { speech.speak(text: text, languageCode: languageCode, rate: rate) } }
        .onDisappear { speech.stop() }
        .onChange(of: rate) { _ in
            switch speech.state {
            case .idle:
                break
            case .speaking, .paused:
                // Restart from beginning with new rate
                speech.speak(text: text, languageCode: languageCode, rate: rate)
            }
        }
        .navigationTitle("Player")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var progress: Double {
        switch speech.state {
        case .idle: 0
        case .speaking(let value): value
        case .paused(let value): value
        }
    }

    private var playPauseIcon: String {
        switch speech.state {
        case .idle, .paused: "play.fill"
        case .speaking: "pause.fill"
        }
    }

    private func toggle() {
        switch speech.state {
        case .idle:
            speech.speak(text: text)
        case .speaking:
            speech.pause()
        case .paused:
            speech.resume()
        }
    }

    private func stop() {
        speech.stop()
    }

    private var previewText: String {
        let sample = text.prefix(200)
        return String(sample)
    }

    private var rateRange: ClosedRange<Double> { 0.3...0.8 }
    private var rateScale: Double {
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        guard base > 0 else { return 1.0 }
        return Double(rate) / base
    }
}
