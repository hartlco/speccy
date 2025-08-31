import Foundation
import SwiftData
import Combine
import CryptoKit

@MainActor
final class DocumentStateManager: ObservableObject {
    static let shared = DocumentStateManager()
    
    @Published private(set) var isPolling = false
    
    private let backendService = TTSBackendService.shared
    private var pollingTimer: Timer?
    private var modelContext: ModelContext?
    
    private init() {}
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        startPolling()
    }
    
    // MARK: - Document Submission
    
    func submitDocumentForGeneration(_ document: SpeechDocument) async {
        guard let config = loadOpenAIConfig() else {
            document.generationState = .failed
            document.errorMessage = "Missing OpenAI API key"
            saveContext()
            return
        }
        
        document.generationState = .submitted
        document.lastSubmittedAt = Date()
        saveContext()
        
        do {
            let authResponse = try await backendService.authenticate(openAIToken: config.apiKey)
            AppLogger.shared.info("Authenticated with backend for document submission: \(document.title)", category: .system)
            
            AppLogger.shared.info("Submitting TTS generation request for: \(document.title), text length: \(document.plainText.count)", category: .system)
            let ttsResponse = try await backendService.generateTTS(
                text: document.plainText,
                voice: config.voice,
                model: config.model,
                format: config.format,
                speed: 1.0,
                openAIToken: config.apiKey
            )
            
            AppLogger.shared.info("TTS response for \(document.title): status=\(ttsResponse.status ?? "nil"), file_id=\(ttsResponse.file_id ?? "nil"), content_hash=\(ttsResponse.content_hash ?? "nil")", category: .system)
            
            guard let status = ttsResponse.status else {
                throw DocumentStateError.invalidResponse
            }
            
            switch status {
            case "ready":
                document.generationState = .ready
                document.backendFileId = ttsResponse.file_id
                document.contentHash = ttsResponse.content_hash
                document.errorMessage = nil
            case "generating":
                document.generationState = .generating
                document.contentHash = ttsResponse.content_hash
                document.errorMessage = nil
            case "failed":
                document.generationState = .failed
                document.errorMessage = ttsResponse.error ?? "Generation failed"
            default:
                document.generationState = .failed
                document.errorMessage = "Unknown status: \(status)"
            }
            
            saveContext()
            
        } catch {
            document.generationState = .failed
            document.errorMessage = error.localizedDescription
            saveContext()
            AppLogger.shared.error("Failed to submit document for generation: \(error)", category: .system)
            
            // If it's a network error, provide more helpful message
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    document.errorMessage = "No internet connection"
                case .cannotConnectToHost:
                    document.errorMessage = "Cannot connect to backend server"
                case .timedOut:
                    document.errorMessage = "Request timed out"
                default:
                    document.errorMessage = "Network error: \(urlError.localizedDescription)"
                }
                saveContext()
            }
        }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        guard pollingTimer == nil else { return }
        
        isPolling = true
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollDocumentStates()
            }
        }
        
        AppLogger.shared.info("Started document state polling", category: .system)
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPolling = false
        AppLogger.shared.info("Stopped document state polling", category: .system)
    }
    
    private func pollDocumentStates() async {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<SpeechDocument>()
        
        do {
            let allDocuments = try modelContext.fetch(descriptor)
            let pendingDocuments = allDocuments.filter { doc in
                doc.currentGenerationState == .submitted || doc.currentGenerationState == .generating
            }
            
            for document in pendingDocuments {
                await checkDocumentStatus(document)
            }
            
        } catch {
            AppLogger.shared.error("Failed to fetch pending documents: \(error)", category: .system)
        }
    }
    
    private func checkDocumentStatus(_ document: SpeechDocument) async {
        guard let contentHash = document.contentHash else {
            // No content hash stored, document might be from old version or failed submission
            AppLogger.shared.warning("No content hash for document \(document.title), skipping status check", category: .system)
            return
        }
        
        do {
            let statusResponse = try await backendService.getFileStatus(contentHash: contentHash)
            AppLogger.shared.info("Status check for \(document.title): \(statusResponse.status ?? "nil")", category: .system)
            
            switch statusResponse.status {
            case "ready":
                document.generationState = .ready
                document.backendFileId = statusResponse.file_id
                document.errorMessage = nil
                AppLogger.shared.info("Document generation completed: \(document.title)", category: .system)
                
            case "generating":
                if document.generationState != .generating {
                    document.generationState = .generating
                }
                
            case "failed":
                document.generationState = .failed
                document.errorMessage = statusResponse.error ?? "Generation failed"
                AppLogger.shared.error("Document generation failed: \(document.title)", category: .system)
                
            default:
                AppLogger.shared.warning("Unknown status for document \(document.title): \(statusResponse.status ?? "nil")", category: .system)
            }
            
            saveContext()
            
        } catch {
            AppLogger.shared.error("Failed to check document status: \(error)", category: .system)
        }
    }
    
    // MARK: - File Download
    
    func downloadGeneratedFile(for document: SpeechDocument) async -> URL? {
        guard document.currentGenerationState == .ready,
              let fileId = document.backendFileId else {
            return nil
        }
        
        do {
            let localURL = try await backendService.downloadFile(fileId: fileId)
            AppLogger.shared.info("Downloaded generated file for: \(document.title)", category: .system)
            return localURL
        } catch {
            AppLogger.shared.error("Failed to download generated file: \(error)", category: .system)
            return nil
        }
    }
    
    // MARK: - Manual Refresh
    
    func refreshDocumentStates() async {
        await pollDocumentStates()
    }
    
    // MARK: - Helper Methods
    
    private func saveContext() {
        guard let modelContext = modelContext else { return }
        
        do {
            try modelContext.save()
        } catch {
            AppLogger.shared.error("Failed to save model context: \(error)", category: .system)
        }
    }
    
    private func loadOpenAIConfig() -> OpenAIConfig? {
        let defaultsKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY")
        let infoKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String
        let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        
        var configPlistKey: String?
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path) {
            configPlistKey = plist["OPENAI_API_KEY"] as? String
        }
        
        guard let apiKey = defaultsKey ?? infoKey ?? envKey ?? configPlistKey, !apiKey.isEmpty else {
            return nil
        }
        
        let model = UserDefaults.standard.string(forKey: "OPENAI_TTS_MODEL") ?? "tts-1"
        let voice = UserDefaults.standard.string(forKey: "OPENAI_TTS_VOICE") ?? "alloy"
        let format = UserDefaults.standard.string(forKey: "OPENAI_TTS_FORMAT") ?? "mp3"
        
        return OpenAIConfig(apiKey: apiKey, model: model, voice: voice, format: format)
    }
    
    private func generateContentHash(for text: String, config: OpenAIConfig) -> String {
        let combined = "\(text)|\(config.model)|\(config.voice)|\(config.format)"
        let data = Data(combined.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Error Types

enum DocumentStateError: Error, LocalizedError {
    case invalidResponse
    case missingConfig
    case submissionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from backend"
        case .missingConfig:
            return "Missing OpenAI configuration"
        case .submissionFailed(let message):
            return "Submission failed: \(message)"
        }
    }
}