import SwiftData
import SwiftUI

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var speechService = SpeechService()
    
    @State var document: SpeechDocument
    @State private var showingEditor = false
    @State private var showingPlayer = false
    @State private var downloadState: DownloadState = .notStarted
    
    enum DownloadState {
        case notStarted
        case downloading(progress: Double)
        case completed
        case failed(Error)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                if case .downloading(let progress) = downloadState {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.blue)
                            Text("Downloading audio...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }
                    .padding()
                    .background(Color.primary.colorInvert().opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if case .failed(let error) = downloadState {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Download failed")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Retry") {
                            startDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding()
                    .background(Color.primary.colorInvert().opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        showingPlayer = true
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Audio")
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
    
    private var canPlay: Bool {
        switch downloadState {
        case .completed:
            return !document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .notStarted, .downloading, .failed:
            return false
        }
    }
    
    private func checkAndStartDownload() {
        // Check if audio is already cached
        if isAudioCached() {
            downloadState = .completed
        } else {
            startDownload()
        }
    }
    
    private func startDownload() {
        guard !document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            downloadState = .completed
            return
        }
        
        downloadState = .downloading(progress: 0)
        
        // Start a silent download by calling speech service
        speechService.preloadAudio(
            text: document.plainText,
            onProgress: { progress in
                downloadState = .downloading(progress: progress)
            },
            onCompletion: { result in
                switch result {
                case .success:
                    downloadState = .completed
                case .failure(let error):
                    downloadState = .failed(error)
                }
            }
        )
    }
    
    private func isAudioCached() -> Bool {
        guard !document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true // Empty documents don't need audio
        }
        
        // Check if we can create a SpeechService instance to check caching
        let tempService = SpeechService()
        return tempService.isAudioCached(for: document.plainText)
    }
}