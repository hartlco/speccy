import SwiftData
import SwiftUI

struct DocumentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var documentStateManager = DocumentStateManager.shared

    @State var document: SpeechDocument
    var isNew: Bool = false
    var onSave: ((SpeechDocument) -> Void)? = nil

    @State private var title: String = ""
    @State private var markdown: String = ""
    @State private var originalContent: String = ""
    var body: some View {
        Form {
            TextField("Title", text: $title)
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
            TextEditor(text: $markdown)
                .frame(minHeight: 240)
        }
        .navigationTitle(document.title.isEmpty ? "New Document" : document.title)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .bold()
                    .disabled(!document.isEditable && !isNew)
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .automatic) {
                Button("Save") { save() }
                    .bold()
                    .disabled(!document.isEditable && !isNew)
            }
            #endif
        }
        .onAppear {
            title = document.title == "Untitled" ? "" : document.title
            markdown = document.markdown
            originalContent = document.plainText
        }
        .disabled(!document.isEditable && !isNew)
    }

    private func cancel() {
        if isNew { dismiss() } else { dismiss() }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
        document.markdown = markdown
        document.updatedAt = .now
        
        if isNew {
            modelContext.insert(document)
        }
        
        do {
            try modelContext.save()
            
            // Submit document to backend for TTS generation if content changed
            let newContent = document.plainText
            if newContent != originalContent && !newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task {
                    await documentStateManager.submitDocumentForGeneration(document)
                }
            }
            
            onSave?(document)
            dismiss()
        } catch {
            print("Failed saving: \(error)")
        }
    }
}
