import Foundation
import SwiftData
import SwiftUI

@Model
final class SpeechDocument {
    var id: UUID = UUID()
    var title: String = ""
    var markdown: String = ""
    var languageCode: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), title: String, markdown: String, languageCode: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.languageCode = languageCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
}
