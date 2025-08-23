import SwiftData
import SwiftUI

struct DocumentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State var document: SpeechDocument
    var isNew: Bool = false

    @State private var title: String = ""
    @State private var markdown: String = ""
    @State private var showingPlayer = false

    var body: some View {
        Form {
            TextField("Title", text: $title)
                .textInputAutocapitalization(.sentences)
            TextEditor(text: $markdown)
                .frame(minHeight: 240)
        }
        .navigationTitle(document.title.isEmpty ? "New Document" : document.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .bold()
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button {
                    showingPlayer = true
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            title = document.title
            markdown = document.markdown
        }
        .sheet(isPresented: $showingPlayer) {
            SpeechPlayerView(text: markdown)
        }
    }

    private func cancel() {
        if isNew { dismiss() } else { dismiss() }
    }

    private func save() {
        document.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.markdown = markdown
        document.updatedAt = .now
        if isNew {
            modelContext.insert(document)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed saving: \(error)")
        }
    }
}
