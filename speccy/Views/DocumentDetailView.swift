import SwiftData
import SwiftUI

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloadManager = DownloadManagerBackend.shared
    @ObservedObject private var playbackManager = PlaybackManager.shared
    @ObservedObject private var speechService = SpeechServiceBackend.shared
    @ObservedObject private var consentManager = TTSConsentManager.shared
    
    @State var document: SpeechDocument
    @State private var showingEditor = false
    @State private var showingPlayer = false
    @State private var isSyncAvailable = false
    
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
                        // Show sync status for completed downloads
                        if let syncState = currentSyncState {
                            syncStatusView(syncState: syncState)
                        }
                    }
                }
                
                // Show sync status for documents without active downloads
                if currentDownloadState == nil, let syncState = currentSyncState {
                    syncStatusView(syncState: syncState)
                }
            }
            .padding()
        }
        .navigationTitle(document.title.isEmpty ? "Document" : document.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay(alignment: .center) {
            if consentManager.isShowingConsentDialog {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    TTSConsentDialog()
                }
            }
        }
        .onAppear {
            checkAndStartDownload()
            // Check sync availability for play button state and sync status UI
            Task {
                AppLogger.shared.info("📱 UI: Checking sync availability for document: \(document.title)", category: .system)
                isSyncAvailable = await speechService.isAudioAvailableInSync(for: document.plainText)
                AppLogger.shared.info("📱 UI: Sync availability result: \(isSyncAvailable)", category: .system)
            }
            // Check and update sync availability in download manager
            downloadManager.checkSyncAvailability(for: document.id.uuidString, text: document.plainText)
            
            // Also refresh sync state in case files were synced while app was inactive
            downloadManager.refreshAllSyncStates()
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                DocumentEditorView(document: document, onSave: { updatedDocument in
                    document = updatedDocument
                    // Re-download audio after editing - ask for consent
                    requestTTSConsent()
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
    
    private var currentDownloadState: DownloadManagerBackend.DownloadState? {
        downloadManager.getDownloadState(for: document.id.uuidString)
    }
    
    private var currentSyncState: DownloadManagerBackend.SyncState? {
        return downloadManager.getSyncState(for: document.id.uuidString)
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
        
        // If no active download, check if audio is cached locally or available in sync
        return downloadManager.isAudioCached(for: document.id.uuidString, text: document.plainText) || isSyncAvailable
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
        
        // Check if audio is already cached locally
        if downloadManager.isAudioCached(for: document.id.uuidString, text: document.plainText) {
            return // Already have audio
        }
        
        if currentDownloadState != nil {
            return // Already downloading or queued
        }
        
        // Check if audio is available in sync before generating new TTS
        Task {
            let isAvailableInSync = await speechService.isAudioAvailableInSync(for: document.plainText)
            AppLogger.shared.info("Audio availability check - isAvailableInSync: \(isAvailableInSync) for document: \(document.title)", category: .system)
            
            if !isAvailableInSync {
                // Audio is not available anywhere, request consent for TTS generation
                AppLogger.shared.info("Requesting TTS consent for document: \(document.title)", category: .speech)
                await MainActor.run {
                    requestTTSConsent()
                }
            } else {
                AppLogger.shared.info("Audio is available in sync, skipping TTS generation for document: \(document.title)", category: .system)
            }
        }
    }
    
    private func requestTTSConsent() {
        AppLogger.shared.info("Calling consentManager.requestTTSGeneration for: \(document.title)", category: .speech)
        consentManager.requestTTSGeneration(
            text: document.plainText,
            title: document.title.isEmpty ? "Untitled" : document.title,
            onApprove: {
                AppLogger.shared.info("User approved TTS generation for: \(self.document.title)", category: .speech)
                self.startDownload()
            },
            onDecline: {
                // User declined, don't start download
                AppLogger.shared.info("User declined TTS generation for document: \(self.document.title)", category: .speech)
            }
        )
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
    
    @ViewBuilder
    private func syncStatusView(syncState: DownloadManagerBackend.SyncState?) -> some View {
        switch syncState {
        case .some(.notSynced):
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                Text("Not synced to backend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
        case .some(.syncing):
            HStack {
                Image(systemName: "arrow.up.to.line.compact")
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)
                Text("Syncing to backend...")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
        case .some(.synced):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Synced to backend")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
        // Backend service handles sync automatically, no need for unavailable state
            
        case .some(.syncFailed(let error)):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync failed")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                    Text(error.localizedDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        
        case .none:
            // No sync state available
            EmptyView()
        }
    }
}