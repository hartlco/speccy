import Foundation
import SwiftUI
import Combine

@MainActor
class TTSConsentManager: ObservableObject {
    static let shared = TTSConsentManager()
    
    @Published var isShowingConsentDialog = false
    
    private var pendingConsent: PendingTTSRequest?
    
    struct PendingTTSRequest {
        let text: String
        let title: String
        let estimatedCost: Double
        let estimatedTime: TimeInterval
        let onApprove: () -> Void
        let onDecline: () -> Void
    }
    
    struct TTSEstimate {
        let characterCount: Int
        let estimatedCost: Double // in USD
        let estimatedTime: TimeInterval // in seconds
        let chunkCount: Int
    }
    
    private init() {}
    
    func requestTTSGeneration(
        text: String,
        title: String,
        onApprove: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        AppLogger.shared.info("TTSConsentManager.requestTTSGeneration called for: '\(title)'", category: .speech)
        let estimate = estimateTTSCost(for: text)
        
        // For very small texts (under 100 characters), auto-approve without asking
        if estimate.characterCount < 100 {
            AppLogger.shared.info("Auto-approving TTS for small text (\(estimate.characterCount) chars)", category: .speech)
            onApprove()
            return
        }
        
        AppLogger.shared.info("Requesting user consent for TTS generation: \(estimate.characterCount) chars, estimated $\(String(format: "%.3f", estimate.estimatedCost))", category: .speech)
        
        pendingConsent = PendingTTSRequest(
            text: text,
            title: title,
            estimatedCost: estimate.estimatedCost,
            estimatedTime: estimate.estimatedTime,
            onApprove: onApprove,
            onDecline: onDecline
        )
        
        AppLogger.shared.info("Setting isShowingConsentDialog = true", category: .speech)
        isShowingConsentDialog = true
    }
    
    func approveTTSGeneration() {
        guard let pending = pendingConsent else { return }
        
        AppLogger.shared.info("User approved TTS generation for '\(pending.title)'", category: .speech)
        pending.onApprove()
        
        pendingConsent = nil
        isShowingConsentDialog = false
    }
    
    func declineTTSGeneration() {
        guard let pending = pendingConsent else { return }
        
        AppLogger.shared.info("User declined TTS generation for '\(pending.title)'", category: .speech)
        pending.onDecline()
        
        pendingConsent = nil
        isShowingConsentDialog = false
    }
    
    func estimateTTSCost(for text: String) -> TTSEstimate {
        let characterCount = text.count
        
        // OpenAI TTS pricing: $0.015 per 1K characters
        let costPer1000Chars = 0.015
        let estimatedCost = Double(characterCount) / 1000.0 * costPer1000Chars
        
        // Rough time estimate: ~150 words per minute for TTS generation + API latency
        let wordsPerMinute = 150.0
        let avgCharsPerWord = 5.0
        let generationTimeMinutes = Double(characterCount) / avgCharsPerWord / wordsPerMinute
        let apiLatencySeconds = 2.0 // Base latency
        let estimatedTime = generationTimeMinutes * 60 + apiLatencySeconds
        
        // Calculate chunks (same logic as SpeechService)
        let chunkCount = max(1, characterCount / 3800 + (characterCount % 3800 > 0 ? 1 : 0))
        
        return TTSEstimate(
            characterCount: characterCount,
            estimatedCost: estimatedCost,
            estimatedTime: estimatedTime,
            chunkCount: chunkCount
        )
    }
    
    var currentEstimate: TTSEstimate? {
        guard let pending = pendingConsent else { return nil }
        return estimateTTSCost(for: pending.text)
    }
    
    var currentRequest: PendingTTSRequest? {
        return pendingConsent
    }
}