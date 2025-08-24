import SwiftData
import SwiftUI

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var playbackManager = PlaybackManager.shared
    @StateObject private var speechService = SpeechService()
    
    @State var document: SpeechDocument
    @State private var showingEditor = false
    @State private var showingPlayer = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Action buttons at top
                HStack(spacing: 12) {
                    Button {
                        if playbackManager.isCurrentSession(documentId: document.id.uuidString) {
                            // If this document is currently playing, show the full player
                            showingPlayer = true
                        } else {
                            // Start new playback session
                            startPlayback()
                        }
                    } label: {
                        HStack {
                            if playbackManager.isCurrentSession(documentId: document.id.uuidString) {
                                if playbackManager.isPlaying {
                                    Image(systemName: "waveform")
                                        .symbolEffect(.variableColor.iterative)
                                } else if playbackManager.isPaused {
                                    Image(systemName: "pause.fill")
                                } else {
                                    Image(systemName: "play.fill")
                                }
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(playButtonText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPlay)
                    
                    Button {
                        showingEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                
                // Document content
                VStack(alignment: .leading, spacing: 12) {
                    Text(document.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if !document.markdown.isEmpty {
                        Text(document.plainText)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text("No content")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.primary.colorInvert().opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Download status
                if let downloadState = currentDownloadState {
                    switch downloadState {
                    case .pending:
                        downloadStatusView(
                            icon: "clock",
                            color: .orange,
                            title: "Queued for download",
                            subtitle: "Waiting to start...",
                            showCancel: true
                        )
                    case .downloading(let progress):
                        downloadStatusView(
                            icon: "arrow.down.circle",
                            color: .blue,
                            title: "Downloading audio...",
                            subtitle: "\(Int(progress * 100))%",
                            progress: progress,
                            showCancel: true
                        )
                    case .failed(let error):
                        downloadStatusView(
                            icon: "exclamationmark.triangle",
                            color: .red,
                            title: "Download failed",
                            subtitle: error.localizedDescription,
                            showRetry: true
                        )
                    case .cancelled:
                        downloadStatusView(
                            icon: "xmark.circle",
                            color: .secondary,
                            title: "Download cancelled",
                            subtitle: "Tap retry to download again",
                            showRetry: true
                        )
                    case .completed:
                        // Don't show anything for completed downloads
                        EmptyView()
                    }
                }
            }
            .padding()
        }
        .navigationTitle(document.title.isEmpty ? "Document" : document.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            checkAndStartDownload()
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                DocumentEditorView(document: document, onSave: { updatedDocument in
                    document = updatedDocument
                    // Re-download audio after editing
                    startDownload()
                })
            }
        }
        .sheet(isPresented: $showingPlayer) {
            SpeechPlayerView(
                text: document.plainText,
                title: document.title,
                languageCode: nil,
                resumeKey: document.id.uuidString
            )
        }
    }
    
    private var currentDownloadState: DownloadManager.DownloadState? {
        downloadManager.getDownloadState(for: document.id.uuidString)
    }
    
    private var canPlay: Bool {
        guard !document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        if let downloadState = currentDownloadState {
            if case .completed = downloadState {
                return true
            }
            return false
        }
        
        // If no active download, check if audio is cached
        return downloadManager.isAudioCached(for: document.id.uuidString, text: document.plainText)
    }
    
    private var playButtonText: String {
        if playbackManager.isCurrentSession(documentId: document.id.uuidString) {
            if playbackManager.isPlaying {
                return "Now Playing"
            } else if playbackManager.isPaused {
                return "Resume"
            } else {
                return "Open Player"
            }
        } else {
            return "Play Audio"
        }
    }
    
    private func startPlayback() {
        playbackManager.startPlayback(
            documentId: document.id.uuidString,
            title: document.title,
            text: document.plainText,
            languageCode: nil,
            resumeKey: document.id.uuidString,
            speechService: speechService
        )
    }
    
    private func checkAndStartDownload() {
        guard !document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return // Empty documents don't need audio
        }
        
        // Check if audio is already cached or downloading
        if downloadManager.isAudioCached(for: document.id.uuidString, text: document.plainText) {
            return // Already have audio
        }
        
        if currentDownloadState != nil {
            return // Already downloading or queued
        }
        
        // Start download
        startDownload()
    }
    
    private func startDownload() {
        downloadManager.startDownload(
            for: document.id.uuidString,
            title: document.title.isEmpty ? "Untitled" : document.title,
            text: document.plainText
        )
    }
    
    @ViewBuilder
    private func downloadStatusView(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        progress: Double? = nil,
        showRetry: Bool = false,
        showCancel: Bool = false
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                HStack(spacing: 8) {
                    if showRetry {
                        Button("Retry") {
                            startDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if showCancel {
                        Button("Cancel") {
                            downloadManager.cancelDownload(for: document.id.uuidString)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                }
            }
            
            if let progress = progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding()
        .background(Color.primary.colorInvert().opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}