import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ""
    @State private var model: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_MODEL") ?? "gpt-4o-mini-tts"
    @State private var voice: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_VOICE") ?? "alloy"
    @State private var format: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_FORMAT") ?? "mp3"
    @State private var defaultEngineRaw: String = UserDefaults.standard.string(forKey: "SPEECH_ENGINE") ?? "system"

    var body: some View {
        Form {
            Section(header: Text("Engine")) {
                Picker("Default Engine", selection: $defaultEngineRaw) {
                    Text("System").tag("system")
                    Text("OpenAI").tag("openAI")
                }
                .pickerStyle(.segmented)
                Text("This engine will be used by default in the player.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("OpenAI"), footer: Text("API key is stored in UserDefaults on device only.")) {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
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
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.bold()
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_API_KEY")
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_TTS_MODEL")
        UserDefaults.standard.set(voice.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_TTS_VOICE")
        UserDefaults.standard.set(format, forKey: "OPENAI_TTS_FORMAT")
        UserDefaults.standard.set(defaultEngineRaw, forKey: "SPEECH_ENGINE")
        dismiss()
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
