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
    private var lastDeletedFilesCheck: String?
    private var lastSyncTimestamp: String?
    private var hasPerformedInitialSync: Bool = false
    
    private init() {}
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        startPolling()
    }
    
    func performInitialSync() async {
        await syncAllFiles()
    }
    
    func performInitialAuthenticationAndSync() async {
        // Try to authenticate with stored API key and sync
        guard let config = loadOpenAIConfig() else {
            AppLogger.shared.info("No OpenAI API key configured, skipping initial sync", category: .system)
            return
        }
        
        AppLogger.shared.info("Attempting initial authentication and sync on app startup", category: .system)
        
        do {
            _ = try await backendService.authenticate(openAIToken: config.apiKey)
            AppLogger.shared.info("Successfully authenticated on app startup", category: .system)
            
            // Small delay to ensure authentication is fully complete
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            await performInitialSyncIfNeeded()
        } catch {
            AppLogger.shared.info("Initial authentication failed (this is normal if no backend is running): \(error)", category: .system)
        }
    }
    
    private func performInitialSyncIfNeeded() async {
        guard !hasPerformedInitialSync else { return }
        hasPerformedInitialSync = true
        AppLogger.shared.info("Performing initial sync after authentication", category: .system)
        await syncAllFiles()
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
            _ = try await backendService.authenticate(openAIToken: config.apiKey)
            AppLogger.shared.info("Authenticated with backend for document submission: \(document.title)", category: .system)
            
            // Trigger initial sync after authentication (with a small delay to ensure auth is fully complete)
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            await performInitialSyncIfNeeded()
            
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
            
            // Check for deleted files from backend
            await checkForDeletedFiles(allDocuments: allDocuments)
            
            // Check for new files from other devices
            await syncNewFiles()
            
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
    
    private func checkForDeletedFiles(allDocuments: [SpeechDocument]) async {
        // Only check if we're authenticated
        guard backendService.isAuthenticated else { return }
        
        do {
            let deletedFilesResponse = try await backendService.getDeletedFiles(since: lastDeletedFilesCheck)
            let deletedFileIds = deletedFilesResponse.deleted_files
            
            if !deletedFileIds.isEmpty {
                AppLogger.shared.info("Found \(deletedFileIds.count) deleted files from backend", category: .system)
                
                // Find documents with deleted backend files and mark them for regeneration
                for document in allDocuments {
                    if let backendFileId = document.backendFileId,
                       deletedFileIds.contains(backendFileId) {
                        AppLogger.shared.info("File deleted on backend for document: \(document.title)", category: .system)
                        
                        // Reset the document generation state
                        document.generationState = .draft
                        document.backendFileId = nil
                        document.errorMessage = "File was deleted from backend"
                        
                        // Stop playback if this document is currently playing
                        let playbackManager = PlaybackManager.shared
                        if playbackManager.isCurrentSession(documentId: document.id.uuidString) {
                            playbackManager.stopPlayback()
                        }
                    }
                }
                
                saveContext()
            }
            
            // Update the last check timestamp
            lastDeletedFilesCheck = ISO8601DateFormatter().string(from: Date())
            
        } catch {
            AppLogger.shared.error("Failed to check for deleted files: \(error)", category: .system)
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
    
    // MARK: - File Sync
    
    private func syncAllFiles() async {
        // Only sync if we're authenticated
        guard backendService.isAuthenticated else { 
            AppLogger.shared.warning("Skipping sync - not authenticated", category: .system)
            return 
        }
        guard let modelContext = modelContext else { 
            AppLogger.shared.warning("Skipping sync - no model context", category: .system)
            return 
        }
        
        AppLogger.shared.info("Starting syncAllFiles", category: .system)
        
        do {
            let allFiles = try await backendService.getAllFiles()
            AppLogger.shared.info("Successfully fetched \(allFiles.count) files from backend", category: .system)
            
            if !allFiles.isEmpty {
                AppLogger.shared.info("Found \(allFiles.count) total files from backend", category: .system)
                
                // Process all files - only create documents for "ready" files
                let readyFiles = allFiles.filter { $0.status == "ready" }
                
                for fileInfo in readyFiles {
                    // Check if we already have a document with this content hash
                    let existingDocs = try modelContext.fetch(FetchDescriptor<SpeechDocument>())
                    let existingDoc = existingDocs.first { $0.contentHash == fileInfo.content_hash }
                    
                    if existingDoc == nil {
                        // Create a new document from the backend file
                        let newDocument = SpeechDocument(
                            title: generateTitleFromText(fileInfo.text_content),
                            markdown: fileInfo.text_content,
                            createdAt: parseBackendTimestamp(fileInfo.created_at) ?? Date(),
                            updatedAt: parseBackendTimestamp(fileInfo.created_at) ?? Date()
                        )
                        
                        // Set the document as ready with backend file info
                        newDocument.generationState = .ready
                        newDocument.backendFileId = fileInfo.id
                        newDocument.contentHash = fileInfo.content_hash
                        
                        modelContext.insert(newDocument)
                        AppLogger.shared.info("Created new document from backend: \(newDocument.title)", category: .system)
                    } else {
                        // Update existing document if it doesn't have backend info
                        if existingDoc?.backendFileId == nil {
                            existingDoc?.backendFileId = fileInfo.id
                            existingDoc?.generationState = .ready
                            AppLogger.shared.info("Updated existing document with backend info: \(existingDoc?.title ?? "")", category: .system)
                        }
                    }
                }
                
                // Save the new/updated documents
                saveContext()
            }
            
        } catch {
            AppLogger.shared.error("Failed to sync all files: \(error)", category: .system)
        }
    }
    
    private func syncNewFiles() async {
        // Only sync if we're authenticated
        guard backendService.isAuthenticated else { return }
        guard let modelContext = modelContext else { return }
        
        // Use last sync timestamp or default to 24 hours ago for initial sync
        let syncTimestamp = lastSyncTimestamp ?? ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        
        do {
            let newFiles = try await backendService.getFilesSince(timestamp: syncTimestamp)
            
            if !newFiles.isEmpty {
                AppLogger.shared.info("Found \(newFiles.count) new files from backend since \(syncTimestamp)", category: .system)
                
                // Process new files - only create documents for "ready" files
                let readyFiles = newFiles.filter { $0.status == "ready" }
                
                for fileInfo in readyFiles {
                    // Check if we already have a document with this content hash
                    let existingDocs = try modelContext.fetch(FetchDescriptor<SpeechDocument>())
                    let existingDoc = existingDocs.first { $0.contentHash == fileInfo.content_hash }
                    
                    if existingDoc == nil {
                        // Create a new document from the backend file
                        let newDocument = SpeechDocument(
                            title: generateTitleFromText(fileInfo.text_content),
                            markdown: fileInfo.text_content,
                            createdAt: parseBackendTimestamp(fileInfo.created_at) ?? Date(),
                            updatedAt: parseBackendTimestamp(fileInfo.created_at) ?? Date()
                        )
                        
                        // Set the document as ready with backend file info
                        newDocument.generationState = .ready
                        newDocument.backendFileId = fileInfo.id
                        newDocument.contentHash = fileInfo.content_hash
                        
                        modelContext.insert(newDocument)
                        AppLogger.shared.info("Created new document from backend: \(newDocument.title)", category: .system)
                    }
                }
                
                // Save the new documents
                saveContext()
            }
            
            // Update the last sync timestamp to now
            lastSyncTimestamp = ISO8601DateFormatter().string(from: Date())
            
        } catch {
            AppLogger.shared.error("Failed to sync new files: \(error)", category: .system)
        }
    }
    
    private func generateTitleFromText(_ text: String) -> String {
        // Generate a title from the first line or first few words
        let lines = text.components(separatedBy: .newlines)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if !firstLine.isEmpty {
            // Take first line, limit to 50 characters
            return String(firstLine.prefix(50))
        } else {
            // Fallback: take first few words
            let words = text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .prefix(5)
            return words.joined(separator: " ")
        }
    }
    
    private func parseBackendTimestamp(_ timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
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