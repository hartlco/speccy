import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logger = AppLogger.shared
    @ObservedObject private var preferences = UserPreferences.shared

    @State private var apiKey: String = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ""
    @State private var model: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_MODEL") ?? "gpt-4o-mini-tts"
    @State private var voice: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_VOICE") ?? "alloy"
    @State private var format: String = UserDefaults.standard.string(forKey: "OPENAI_TTS_FORMAT") ?? "mp3"
    @State private var backendURL: String = UserDefaults.standard.string(forKey: "BACKEND_BASE_URL") ?? ""
    @State private var showingLogs = false
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
            
            Section(header: Text("Backend Server"), footer: Text("Leave empty to use default server. Format: http://localhost:3000")) {
                TextField("Backend URL", text: $backendURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }
            
            Section("Playback") {
                HStack {
                    Text("Default Speed")
                    Spacer()
                    Text(String(format: "%.1fx", preferences.playbackSpeed))
                        .foregroundStyle(.secondary)
                }
                Picker("Speed", selection: $preferences.playbackSpeed) {
                    ForEach(preferences.availablePlaybackSpeeds, id: \.self) { speed in
                        Text(String(format: "%.1fx", speed)).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            
            Section("Debugging") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Application Logs")
                            .font(.headline)
                        Text("View system logs for debugging")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View Logs") {
                        showingLogs = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    Text("Total Log Entries")
                    Spacer()
                    Text("\(logger.logs.count)")
                        .foregroundStyle(.secondary)
                }
                
                if !logger.logs.isEmpty {
                    Button("Clear All Logs") {
                        logger.clearLogs()
                    }
                    .foregroundStyle(.red)
                }
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
        .sheet(isPresented: $showingLogs) {
            LogsView()
        }
    }

    private func save() {
        UserDefaults.standard.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_API_KEY")
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_TTS_MODEL")
        UserDefaults.standard.set(voice.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "OPENAI_TTS_VOICE")
        UserDefaults.standard.set(format, forKey: "OPENAI_TTS_FORMAT")
        UserDefaults.standard.set(backendURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "BACKEND_BASE_URL")
        dismiss()
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
