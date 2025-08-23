import AVFoundation
import Combine
import Foundation

/// Simple TTS service using AVSpeechSynthesizer with background audio support.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case speaking(progress: Double)
        case paused(progress: Double)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentUtterance: AVSpeechUtterance?

    private let synthesizer = AVSpeechSynthesizer()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        #else
        // macOS does not use AVAudioSession
        #endif
    }

    func speak(text: String, voiceIdentifier: String? = nil, languageCode: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        stop()
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
    }

    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }

    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentUtterance = nil
        state = .idle
    }
}

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
        case .idle:
            break
        }
    }
}
