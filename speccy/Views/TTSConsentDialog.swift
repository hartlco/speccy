import SwiftUI

struct TTSConsentDialog: View {
    @ObservedObject private var consentManager = TTSConsentManager.shared
    @ObservedObject private var speechService = SpeechService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("Generate Audio")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let request = consentManager.currentRequest {
                    Text("for \"\(request.title)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            
            // Cost and time estimates
            if let estimate = consentManager.currentEstimate {
                VStack(spacing: 12) {
                    HStack {
                        Label("\(estimate.characterCount) characters", systemImage: "doc.text")
                            .font(.subheadline)
                        Spacer()
                    }
                    
                    HStack {
                        Label("~\(estimate.chunkCount) chunks", systemImage: "rectangle.split.3x1")
                            .font(.subheadline)
                        Spacer()
                    }
                    
                    HStack {
                        Label("~\(formatTime(estimate.estimatedTime))", systemImage: "clock")
                            .font(.subheadline)
                        Spacer()
                    }
                    
                    HStack {
                        Label("~$\(String(format: "%.3f", estimate.estimatedCost))", systemImage: "dollarsign.circle")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        Spacer()
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            
            // CloudKit check info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "icloud")
                        .foregroundStyle(.blue)
                    Text("Checking iCloud for existing audio...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                Text("We'll first check if this audio is already available on your other devices before generating new audio.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    consentManager.declineTTSGeneration()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
                
                Button("Generate Audio") {
                    consentManager.approveTTSGeneration()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .frame(maxWidth: 360)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            let minutes = Int(seconds) / 60
            let remainingSeconds = Int(seconds) % 60
            if remainingSeconds == 0 {
                return "\(minutes)m"
            } else {
                return "\(minutes)m \(remainingSeconds)s"
            }
        }
    }
}