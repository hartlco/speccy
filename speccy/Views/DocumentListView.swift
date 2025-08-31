import SwiftData
import SwiftUI

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpeechDocument.updatedAt, order: .reverse) private var documents: [SpeechDocument]
    @ObservedObject private var documentStateManager = DocumentStateManager.shared

    @State private var showingNew = false
    @State private var showingSettings = false
    @State private var showingDownloads = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(documents) { doc in
                    NavigationLink(value: doc) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doc.title).font(.headline)
                                Text(doc.markdown)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                statusIndicator(for: doc)
                                if doc.canDownload {
                                    Button(action: {
                                        downloadDocument(doc)
                                    }) {
                                        Image(systemName: "arrow.down.circle")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .opacity(doc.currentGenerationState == .generating ? 0.6 : 1.0)
                }
                .onDelete(perform: delete)
            }
            .refreshable {
                await documentStateManager.refreshDocumentStates()
            }
            .navigationTitle("Documents")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button(action: { showingSettings = true }) { 
                            Image(systemName: "gearshape") 
                        }
                        Button(action: { showingDownloads = true }) { 
                            ZStack {
                                Image(systemName: "arrow.down.circle")
                                if hasActiveGenerations {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingNew = true }) { Image(systemName: "plus") }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingSettings = true }) { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingDownloads = true }) { 
                        ZStack {
                            Image(systemName: "arrow.down.circle")
                            if hasActiveGenerations {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingNew = true }) { Image(systemName: "plus") }
                }
                #endif
            }
            .navigationDestination(for: SpeechDocument.self) { doc in
                DocumentDetailView(document: doc)
            }
            .sheet(isPresented: $showingNew) {
                NavigationStack {
                    DocumentEditorView(
                        document: SpeechDocument(title: "", markdown: ""), 
                        isNew: true
                    )
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingDownloads) {
                DownloadsView()
            }
        }
        .onAppear {
            documentStateManager.configure(with: modelContext)
        }
    }
    
    // MARK: - Helper Methods and Properties
    
    private var hasActiveGenerations: Bool {
        documents.contains { doc in
            doc.currentGenerationState == .submitted || doc.currentGenerationState == .generating
        }
    }
    
    @ViewBuilder
    private func statusIndicator(for document: SpeechDocument) -> some View {
        switch document.currentGenerationState {
        case .draft:
            Label("Draft", systemImage: "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .submitted:
            Label("Submitted", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.orange)
        case .generating:
            Label("Generating", systemImage: "gear")
                .font(.caption)
                .foregroundStyle(.blue)
                .symbolEffect(.rotate)
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
    
    private func downloadDocument(_ document: SpeechDocument) {
        Task {
            if let localURL = await documentStateManager.downloadGeneratedFile(for: document) {
                // File downloaded successfully - could trigger playback or show notification
                AppLogger.shared.info("Downloaded file for \(document.title)", category: .system)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(documents[index]) }
        do { try modelContext.save() } catch { print(error.localizedDescription) }
    }
}

private let sampleMD: String = """
# Welcome to Speccy

Paste or write Markdown here and tap Play to hear it.

- Supports background audio while locked
- Uses system Voices

"""
