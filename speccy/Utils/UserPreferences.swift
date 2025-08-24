import Foundation
import Combine

@MainActor
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    private init() {
        // Load saved preferences
        let savedSpeed = UserDefaults.standard.float(forKey: Keys.playbackSpeed)
        playbackSpeed = savedSpeed == 0 ? 1.0 : savedSpeed
    }
    
    private struct Keys {
        static let playbackSpeed = "PLAYBACK_SPEED"
    }
    
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            UserDefaults.standard.set(playbackSpeed, forKey: Keys.playbackSpeed)
        }
    }
    
    // Available speed options
    let availablePlaybackSpeeds: [Float] = [0.5, 0.7, 1.0, 1.2, 1.6, 2.0]
    
    func resetToDefaults() {
        playbackSpeed = 1.0
    }
}