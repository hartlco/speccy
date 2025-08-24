import SwiftUI

struct LogsView: View {
    @ObservedObject private var logger = AppLogger.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack {
                // Filters
                VStack(spacing: 12) {
                    HStack {
                        Text("Log Level:")
                        Spacer()
                        Picker("Level", selection: $logger.minimumLevel) {
                            ForEach(AppLogger.LogLevel.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Text("Categories:")
                            ForEach(AppLogger.Category.allCases, id: \.self) { category in
                                Toggle(category.rawValue, isOn: Binding(
                                    get: { logger.enabledCategories.contains(category) },
                                    set: { enabled in
                                        if enabled {
                                            logger.enabledCategories.insert(category)
                                        } else {
                                            logger.enabledCategories.remove(category)
                                        }
                                    }
                                ))
                                .toggleStyle(.button)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                
                // Logs List
                if filteredLogs.isEmpty {
                    ContentUnavailableView(
                        "No Logs",
                        systemImage: "doc.text",
                        description: Text("No logs match the current filters")
                    )
                } else {
                    List {
                        ForEach(filteredLogs) { log in
                            LogEntryView(entry: log)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Logs (\(filteredLogs.count))")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Actions") {
                        Button("Clear All") {
                            logger.clearLogs()
                        }
                        Button("Export Logs") {
                            exportLogs()
                        }
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Clear All") {
                        logger.clearLogs()
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Export") {
                        exportLogs()
                    }
                }
                #endif
            }
        }
    }
    
    private var filteredLogs: [AppLogger.LogEntry] {
        let categoryFiltered = logger.filteredLogs
        
        if searchText.isEmpty {
            return categoryFiltered
        } else {
            return categoryFiltered.filter { entry in
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.category.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private func exportLogs() {
        let content = logger.exportLogs()
        
        #if os(iOS)
        // For iOS, we could implement sharing later
        UIPasteboard.general.string = content
        #else
        // For macOS, copy to pasteboard for now
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        #endif
    }
}

struct LogEntryView: View {
    let entry: AppLogger.LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Level indicator
                HStack(spacing: 4) {
                    Image(systemName: entry.level.icon)
                        .foregroundStyle(entry.level.color)
                        .font(.caption)
                    Text(entry.level.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(entry.level.color)
                }
                .frame(width: 60, alignment: .leading)
                
                // Category
                Text(entry.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.blue)
                
                Spacer()
                
                // Timestamp
                Text(entry.formattedTime)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            
            // Message
            Text(entry.message)
                .font(.caption)
                .lineLimit(isExpanded ? nil : 3)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    LogsView()
}