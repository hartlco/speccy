import Foundation
import SwiftUI
import Combine

@MainActor
class AppLogger: ObservableObject {
    static let shared = AppLogger()
    
    enum LogLevel: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var color: Color {
            switch self {
            case .debug: return .secondary
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .debug: return "gear"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            }
        }
    }
    
    enum Category: String, CaseIterable {
        case speech = "SPEECH"
        case download = "DOWNLOAD"
        case chunks = "CHUNKS"
        case cache = "CACHE"
        case playback = "PLAYBACK"
        case system = "SYSTEM"
    }
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let category: Category
        let message: String
        
        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
        
        var fullMessage: String {
            "[\(formattedTime)] [\(level.rawValue)] [\(category.rawValue)] \(message)"
        }
    }
    
    @Published private(set) var logs: [LogEntry] = []
    @Published var enabledCategories: Set<Category> = Set(Category.allCases)
    @Published var minimumLevel: LogLevel = .debug
    
    private let maxLogCount = 1000
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .info, category: Category = .system) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        
        logs.append(entry)
        
        // Keep log count manageable
        if logs.count > maxLogCount {
            logs.removeFirst(logs.count - maxLogCount)
        }
        
        // Also print to console for debugging
        print(entry.fullMessage)
    }
    
    func debug(_ message: String, category: Category = .system) {
        log(message, level: .debug, category: category)
    }
    
    func info(_ message: String, category: Category = .system) {
        log(message, level: .info, category: category)
    }
    
    func warning(_ message: String, category: Category = .system) {
        log(message, level: .warning, category: category)
    }
    
    func error(_ message: String, category: Category = .system) {
        log(message, level: .error, category: category)
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    var filteredLogs: [LogEntry] {
        logs.filter { entry in
            enabledCategories.contains(entry.category) &&
            shouldIncludeLevel(entry.level)
        }
    }
    
    private func shouldIncludeLevel(_ level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warning, .error]
        guard let currentIndex = levels.firstIndex(of: minimumLevel),
              let entryIndex = levels.firstIndex(of: level) else { return true }
        return entryIndex >= currentIndex
    }
    
    func exportLogs() -> String {
        filteredLogs.map { $0.fullMessage }.joined(separator: "\n")
    }
}