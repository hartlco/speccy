import Foundation
import Combine

struct TTSRequest: Codable {
    let text: String
    let voice: String
    let model: String
    let format: String
    let speed: Double
    let openai_token: String
}

struct TTSResponse: Codable {
    let file_id: String?
    let content_hash: String?
    let status: String?
    let url: String?
    let expires_at: String?
    let error: String?
    let message: String?
}

struct AuthRequest: Codable {
    let openai_token: String
}

struct AuthResponse: Codable {
    let user_id: String?
    let session_token: String?
    let error: String?
    let message: String?
}

struct FileStatusResponse: Codable {
    let status: String?
    let file_id: String?
    let expires_at: String?
    let error: String?
    let message: String?
}

@MainActor
class TTSBackendService: NSObject, ObservableObject {
    static let shared = TTSBackendService()
    
    private let baseURL = "http://localhost:3000" // TODO: Configure for production
    private var sessionToken: String?
    
    @Published var isAuthenticated: Bool = false
    @Published var currentUserId: String?
    
    override init() {
        super.init()
    }
    
    // MARK: - Authentication
    
    func authenticate(openAIToken: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(baseURL)/auth/verify") else {
            throw TTSBackendError.invalidURL
        }
        
        let request = AuthRequest(openai_token: openAIToken)
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSBackendError.invalidResponse
        }
        
        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        
        if httpResponse.statusCode == 200 {
            self.sessionToken = authResponse.session_token
            self.isAuthenticated = true
            self.currentUserId = authResponse.user_id
            return authResponse
        } else {
            self.isAuthenticated = false
            self.currentUserId = nil
            throw TTSBackendError.authenticationFailed(authResponse.message ?? "Authentication failed")
        }
    }
    
    func logout() {
        sessionToken = nil
        isAuthenticated = false
        currentUserId = nil
    }
    
    // MARK: - TTS Generation
    
    func generateTTS(
        text: String,
        voice: String,
        model: String,
        format: String = "mp3",
        speed: Double = 1.0,
        openAIToken: String
    ) async throws -> TTSResponse {
        guard let url = URL(string: "\(baseURL)/tts/generate") else {
            throw TTSBackendError.invalidURL
        }
        
        guard let token = sessionToken else {
            throw TTSBackendError.notAuthenticated
        }
        
        let request = TTSRequest(
            text: text,
            voice: voice,
            model: model,
            format: format,
            speed: speed,
            openai_token: openAIToken
        )
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSBackendError.invalidResponse
        }
        
        let ttsResponse = try JSONDecoder().decode(TTSResponse.self, from: data)
        
        if httpResponse.statusCode == 200 {
            return ttsResponse
        } else {
            throw TTSBackendError.ttsGenerationFailed(ttsResponse.message ?? "TTS generation failed")
        }
    }
    
    // MARK: - File Status
    
    func getFileStatus(contentHash: String) async throws -> FileStatusResponse {
        guard let url = URL(string: "\(baseURL)/tts/status/\(contentHash)") else {
            throw TTSBackendError.invalidURL
        }
        
        guard let token = sessionToken else {
            throw TTSBackendError.notAuthenticated
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSBackendError.invalidResponse
        }
        
        let statusResponse = try JSONDecoder().decode(FileStatusResponse.self, from: data)
        
        if httpResponse.statusCode == 200 {
            return statusResponse
        } else {
            throw TTSBackendError.statusCheckFailed(statusResponse.message ?? "Status check failed")
        }
    }
    
    // MARK: - File Download
    
    func downloadFile(fileId: String) async throws -> URL {
        guard let url = URL(string: "\(baseURL)/files/\(fileId)") else {
            throw TTSBackendError.invalidURL
        }
        
        guard let token = sessionToken else {
            throw TTSBackendError.notAuthenticated
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (tempURL, response) = try await URLSession.shared.download(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSBackendError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            // Move to permanent location
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let permanentURL = documentsPath.appendingPathComponent("\(fileId).mp3") // TODO: Get correct extension
            
            try? FileManager.default.removeItem(at: permanentURL) // Remove if exists
            try FileManager.default.moveItem(at: tempURL, to: permanentURL)
            
            return permanentURL
        } else {
            throw TTSBackendError.downloadFailed("Download failed with status \(httpResponse.statusCode)")
        }
    }
    
    // MARK: - File Deletion
    
    func deleteFile(fileId: String) async throws {
        guard let url = URL(string: "\(baseURL)/tts/delete/\(fileId)") else {
            throw TTSBackendError.invalidURL
        }
        
        guard let token = sessionToken else {
            throw TTSBackendError.notAuthenticated
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSBackendError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw TTSBackendError.deletionFailed("Deletion failed with status \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Error Types

enum TTSBackendError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case notAuthenticated
    case authenticationFailed(String)
    case ttsGenerationFailed(String)
    case statusCheckFailed(String)
    case downloadFailed(String)
    case deletionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .notAuthenticated:
            return "Not authenticated - please login first"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .ttsGenerationFailed(let message):
            return "TTS generation failed: \(message)"
        case .statusCheckFailed(let message):
            return "Status check failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .deletionFailed(let message):
            return "Deletion failed: \(message)"
        }
    }
}