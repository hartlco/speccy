import SwiftData
import SwiftUI

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpeechDocument.updatedAt, order: .reverse) private var documents: [SpeechDocument]

    @State private var showingNew = false
    @State private var showingSettings = false

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingNew = true }) { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingSettings = true }) { Image(systemName: "gearshape") }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingNew = true }) { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingSettings = true }) { Image(systemName: "gearshape") }
                }
                #endif
                ToolbarItem(placement: .automatic) {
                    NavigationLink(value: SpeechDocument(title: "Sample", markdown: sampleMD)) {
                        Image(systemName: "play.circle")
                    }.hidden() // placeholder for toolbar layout if needed
                }
            }
            .navigationDestination(for: SpeechDocument.self) { doc in
                DocumentDetailView(document: doc)
            }
            .sheet(isPresented: $showingNew) {
                NavigationStack {
                    DocumentEditorView(
                        document: SpeechDocument(title: "Untitled", markdown: ""), 
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
