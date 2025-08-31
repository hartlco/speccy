import SwiftData
import SwiftUI

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var documentStateManager = DocumentStateManager.shared
    @ObservedObject private var playbackManager = PlaybackManager.shared
    @ObservedObject private var speechService = SpeechServiceBackend.shared
    
    @State var document: SpeechDocument
    @State private var showingEditor = false
    @State private var showingPlayer = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Action buttons at top
                HStack(spacing: 12) {
                    // Play/Download button
                    if document.canDownload {
                        Button {
                            downloadAndPlay()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                Text("Download & Play")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if canPlay {
                        Button {
                            if playbackManager.isCurrentSession(documentId: document.id.uuidString) {
                                showingPlayer = true
                            } else {
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
                    } else {
                        Button {
                            // Disabled button for non-playable documents
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Not Available")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                    }
                    
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
                    .disabled(!document.isEditable)
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
                
                // Generation status
                generationStatusView()
            }
            .padding()
        }
        .navigationTitle(document.title.isEmpty ? "Document" : document.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            documentStateManager.configure(with: modelContext)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                DocumentEditorView(document: document, onSave: { updatedDocument in
                    document = updatedDocument
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
    
    // MARK: - Helper Methods and Properties
    
    private var canPlay: Bool {
        guard !document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return speechService.isAudioCached(for: document.plainText)
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
    
    private func downloadAndPlay() {
        Task {
            if let localURL = await documentStateManager.downloadGeneratedFile(for: document) {
                // File downloaded successfully, now start playback
                await MainActor.run {
                    startPlayback()
                }
            }
        }
    }
    
    @ViewBuilder
    private func generationStatusView() -> some View {
        switch document.currentGenerationState {
        case .draft:
            HStack {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                Text("Draft - Save to generate audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
        case .submitted:
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.orange)
                Text("Submitted for generation")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
        case .generating:
            HStack {
                Image(systemName: "gear")
                    .foregroundStyle(.blue)
                    .symbolEffect(.rotate)
                Text("Generating audio...")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
        case .ready:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Audio ready for download")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
        case .failed:
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generation failed")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                    if let errorMessage = document.errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Retry") {
                    Task {
                        await documentStateManager.submitDocumentForGeneration(document)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}