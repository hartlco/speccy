import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ""
    @State private var model: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_MODEL") ?? "gpt-4o-mini-tts"
    @State private var voice: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_VOICE") ?? "alloy"
    @State private var format: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_FORMAT") ?? "mp3"
    var body: some View {
        Form {
            Section(header: Text("OpenAI"), footer: Text("API key is stored in UserDefaults on device only.")) {
                SecureField("API Key", text: $apiKey)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
                    #endif
                TextField("Model", text: $model)
                TextField("Voice", text: $voice)
                Picker("Format", selection: $format) {
                    Text("mp3").tag("mp3")
                    Text("aac").tag("aac")
                    Text("wav").tag("wav")
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.bold()
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .automatic) {
                Button("Save") { save() }.bold()
            }
            #endif
        }
    }

    private func save() {
        UserDefaults.standard.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_API_KEY")
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_TTS_MODEL")
        UserDefaults.standard.set(voice.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_TTS_VOICE")
        UserDefaults.standard.set(format, forKey: "OPENAI_TTS_FORMAT")
        dismiss()
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
