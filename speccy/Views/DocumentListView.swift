import SwiftData
import SwiftUI

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpeechDocument.updatedAt, order: .reverse) private var documents: [SpeechDocument]
    @ObservedObject private var downloadManager = DownloadManagerBackend.shared

    @State private var showingNew = false
    @State private var showingSettings = false
    @State private var showingDownloads = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(documents) { doc in
                    NavigationLink(value: doc) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(doc.title).font(.headline)
                            Text(doc.markdown)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
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
                                if downloadManager.hasActiveDownloads {
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
                            if downloadManager.hasActiveDownloads {
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
                        isNew: true,
                        onSave: { _ in
                            // After creating a new document, the navigation will show it in detail view
                            // which will automatically trigger the download
                        }
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
