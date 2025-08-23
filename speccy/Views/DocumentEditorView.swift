import SwiftData
import SwiftUI
import AVFoundation

struct DocumentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State var document: SpeechDocument
    var isNew: Bool = false

    @State private var title: String = ""
    @State private var markdown: String = ""
    @State private var showingPlayer = false
    @State private var selectedLanguageCode: String = Locale.current.identifier

    var body: some View {
        Form {
            TextField("Title", text: $title)
                .textInputAutocapitalization(.sentences)
            TextEditor(text: $markdown)
                .frame(minHeight: 240)
            Picker("Language", selection: $selectedLanguageCode) {
                ForEach(availableLanguageCodes, id: \.self) { code in
                    Text(localeDisplayName(for: code)).tag(code)
                }
            }
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
            if let code = document.languageCode { selectedLanguageCode = code }
        }
        .sheet(isPresented: $showingPlayer) {
            SpeechPlayerView(text: markdown, languageCode: selectedLanguageCode)
        }
    }

    private func cancel() {
        if isNew { dismiss() } else { dismiss() }
    }

    private func save() {
        document.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.markdown = markdown
        document.languageCode = selectedLanguageCode
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

private let availableLanguageCodes: [String] = {
    // Build from available voices; fall back to common locales
    let codes = AVSpeechSynthesisVoice.speechVoices().map { $0.language }
    let unique = Array(Set(codes)).sorted()
    if unique.isEmpty { return ["en-US", "en-GB", "de-DE", "fr-FR", "es-ES", "it-IT"] }
    return unique
}()

private func localeDisplayName(for code: String) -> String {
    let locale = Locale(identifier: code)
    let language = locale.localizedString(forIdentifier: code) ?? code
    return language
}
