import Foundation
import SwiftData
import SwiftUI

enum DocumentGenerationState: String, CaseIterable, Codable {
    case draft = "draft"
    case submitted = "submitted"
    case generating = "generating"
    case ready = "ready"
    case failed = "failed"
}

@Model
final class SpeechDocument {
    var id: UUID = UUID()
    var title: String = ""
    var markdown: String = ""
    var languageCode: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var generationState: DocumentGenerationState?
    var backendFileId: String?
    var contentHash: String?
    var lastSubmittedAt: Date?
    var errorMessage: String?

    init(id: UUID = UUID(), title: String, markdown: String, languageCode: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.languageCode = languageCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.generationState = DocumentGenerationState.draft
    }
}

extension SpeechDocument {
    var plainText: String {
        // Prefer high-quality Markdown parsing when available
        if #available(iOS 15.0, macOS 12.0, *) {
            if let attributed = try? AttributedString(markdown: markdown) {
                return String(attributed.characters)
            }
        }
        // Fallback: very light-weight Markdown stripping
        return markdown
            .replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[#*_>\-]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var currentGenerationState: DocumentGenerationState {
        return generationState ?? .draft
    }
    
    var isEditable: Bool {
        return currentGenerationState == .draft || currentGenerationState == .failed
    }
    
    var isDeletable: Bool {
        return true
    }
    
    var canDownload: Bool {
        return currentGenerationState == .ready && backendFileId != nil
    }
    
    var statusText: String {
        switch currentGenerationState {
        case .draft:
            return "Draft"
        case .submitted:
            return "Submitted"
        case .generating:
            return "Generating..."
        case .ready:
            return "Ready"
        case .failed:
            return "Failed"
        }
    }
}
