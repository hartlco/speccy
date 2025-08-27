import Foundation
import SwiftData
import CryptoKit

@Model
final class TTSAudioFile {
    var contentHash: String = ""
    var filename: String = ""
    var fileSize: Int64 = 0
    var model: String = ""
    var voice: String = ""
    var format: String = ""
    var createdAt: Date = Date()
    var iCloudURL: URL?
    
    init(contentHash: String, filename: String, fileSize: Int64, model: String, voice: String, format: String, createdAt: Date = .now, iCloudURL: URL? = nil) {
        self.contentHash = contentHash
        self.filename = filename
        self.fileSize = fileSize
        self.model = model
        self.voice = voice
        self.format = format
        self.createdAt = createdAt
        self.iCloudURL = iCloudURL
    }
}

extension TTSAudioFile {
    static func contentHash(for text: String, model: String, voice: String, format: String) -> String {
        let combined = [model, voice, format, text].joined(separator: "|")
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}