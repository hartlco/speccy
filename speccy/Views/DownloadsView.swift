import SwiftUI

struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    iCloudStatusView()
                } header: {
                    Text("Sync Status")
                }
                
                if downloadManager.downloads.isEmpty {
                    ContentUnavailableView(
                        "No Downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Audio downloads will appear here")
                    )
                } else {
                    ForEach(downloadManager.downloads) { download in
                        DownloadRowView(download: download)
                    }
                    .onDelete(perform: deleteDownloads)
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !downloadManager.downloads.isEmpty {
                        Button("Clean Up") {
                            downloadManager.cleanupOldDownloads()
                        }
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    if !downloadManager.downloads.isEmpty {
                        Button("Clean Up") {
                            downloadManager.cleanupOldDownloads()
                        }
                    }
                }
                #endif
            }
        }
    }
    
    private func deleteDownloads(at offsets: IndexSet) {
        for index in offsets {
            let download = downloadManager.downloads[index]
            downloadManager.removeDownload(download.id)
        }
    }
}

struct DownloadRowView: View {
    let download: DownloadManager.DownloadItem
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(download.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                
                Spacer()
                
                statusIcon
            }
            
            // Progress bar for active downloads
            if case .downloading(let progress) = download.state {
                HStack {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                if case .failed = download.state {
                    Button("Retry") {
                        downloadManager.retryDownload(download.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if download.isActive {
                    Button("Cancel") {
                        downloadManager.cancelDownload(for: download.documentId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                }
                
                Spacer()
                
                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusText: String {
        switch download.state {
        case .pending:
            return "Waiting to start..."
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .completed:
            return "Completed"
        case .failed(let error):
            return "Failed: \(error.localizedDescription)"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    private var statusColor: Color {
        switch download.state {
        case .pending:
            return .orange
        case .downloading:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch download.state {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.orange)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
    
    private var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: download.createdAt, relativeTo: Date())
    }
}

#Preview {
    DownloadsView()
}