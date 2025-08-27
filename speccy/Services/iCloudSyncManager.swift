import Foundation
import SwiftData
import CloudKit
import Combine

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
class iCloudSyncManager: ObservableObject {
    static let shared = iCloudSyncManager()
    
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var iCloudAvailable = false
    
    enum SyncStatus {
        case idle
        case syncing
        case error(String)
    }
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private var modelContext: ModelContext?
    
    private init() {
        self.container = CKContainer(identifier: "iCloud.com.speccy.documents")
        self.privateDatabase = container.privateCloudDatabase
        checkiCloudStatus()
    }
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    private func checkiCloudStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.iCloudAvailable = true
                    AppLogger.shared.info("iCloud is available", category: .sync)
                case .noAccount:
                    self?.iCloudAvailable = false
                    AppLogger.shared.warning("No iCloud account available", category: .sync)
                case .restricted, .couldNotDetermine:
                    self?.iCloudAvailable = false
                    AppLogger.shared.warning("iCloud access restricted", category: .sync)
                case .temporarilyUnavailable:
                    self?.iCloudAvailable = false
                    AppLogger.shared.warning("iCloud temporarily unavailable", category: .sync)
                @unknown default:
                    self?.iCloudAvailable = false
                }
            }
        }
    }
    
    // MARK: - Audio File Sync
    
    func syncAudioFileToiCloud(localURL: URL, contentHash: String, model: String, voice: String, format: String) async throws {
        guard iCloudAvailable else { throw SyncError.iCloudUnavailable }
        guard let modelContext = modelContext else { throw SyncError.notConfigured }
        
        syncStatus = .syncing
        AppLogger.shared.info("Starting iCloud sync for audio file with hash: \(contentHash)", category: .sync)
        
        do {
            // First check if this file already exists in CloudKit
            if try await audioFileExists(contentHash: contentHash) {
                AppLogger.shared.info("Audio file already exists in iCloud", category: .sync)
                syncStatus = .idle
                return
            }
            
            // Upload to iCloud Documents
            let iCloudURL = try await uploadAudioFile(localURL: localURL, filename: "\(contentHash).\(format)")
            
            // Check if record already exists (since we can't use unique constraints with CloudKit)
            let predicate = #Predicate<TTSAudioFile> { $0.contentHash == contentHash }
            let descriptor = FetchDescriptor<TTSAudioFile>(predicate: predicate)
            let existingFiles = try modelContext.fetch(descriptor)
            
            if existingFiles.isEmpty {
                // Create new database record
                let audioFile = TTSAudioFile(
                    contentHash: contentHash,
                    filename: "\(contentHash).\(format)",
                    fileSize: try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0,
                    model: model,
                    voice: voice,
                    format: format,
                    iCloudURL: iCloudURL
                )
                
                modelContext.insert(audioFile)
                try modelContext.save()
            } else {
                // Update existing record with iCloud URL if needed
                if let existingFile = existingFiles.first, existingFile.iCloudURL != iCloudURL {
                    existingFile.iCloudURL = iCloudURL
                    try modelContext.save()
                }
            }
            
            syncStatus = .idle
            AppLogger.shared.info("Successfully synced audio file to iCloud", category: .sync)
            
        } catch {
            syncStatus = .error(error.localizedDescription)
            AppLogger.shared.error("Failed to sync audio file to iCloud: \(error)", category: .sync)
            throw error
        }
    }
    
    func downloadAudioFileFromiCloud(contentHash: String) async throws -> URL? {
        guard iCloudAvailable else { throw SyncError.iCloudUnavailable }
        guard let modelContext = modelContext else { throw SyncError.notConfigured }
        
        // Check if we have this audio file record
        let predicate = #Predicate<TTSAudioFile> { $0.contentHash == contentHash }
        let descriptor = FetchDescriptor<TTSAudioFile>(predicate: predicate)
        
        guard let audioFile = try modelContext.fetch(descriptor).first,
              let iCloudURL = audioFile.iCloudURL else {
            return nil
        }
        
        // Download from iCloud Documents to local cache
        let localCacheURL = cacheDirectory().appendingPathComponent(audioFile.filename)
        
        if FileManager.default.fileExists(atPath: localCacheURL.path) {
            return localCacheURL
        }
        
        return try await downloadFile(from: iCloudURL, to: localCacheURL)
    }
    
    private func audioFileExists(contentHash: String) async throws -> Bool {
        guard let modelContext = modelContext else { return false }
        
        let predicate = #Predicate<TTSAudioFile> { $0.contentHash == contentHash }
        let descriptor = FetchDescriptor<TTSAudioFile>(predicate: predicate)
        
        let results = try modelContext.fetch(descriptor)
        return !results.isEmpty
    }
    
    private func uploadAudioFile(localURL: URL, filename: String) async throws -> URL {
        let iCloudDocumentsURL = try iCloudDocumentsDirectory()
        let destinationURL = iCloudDocumentsURL.appendingPathComponent("AudioCache").appendingPathComponent(filename)
        
        // Ensure directory exists
        let cacheDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        // Copy file to iCloud Documents
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: localURL, to: destinationURL)
        
        return destinationURL
    }
    
    private func downloadFile(from iCloudURL: URL, to localURL: URL) async throws -> URL {
        // Ensure local directory exists
        let localDir = localURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: localDir.path) {
            try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        }
        
        // Check if file needs to be downloaded from iCloud
        var isDownloaded: AnyObject?
        try (iCloudURL as NSURL).getResourceValue(&isDownloaded, forKey: .ubiquitousItemDownloadingStatusKey)
        
        // Simple approach: if the file doesn't exist locally, try to download it
        if !FileManager.default.fileExists(atPath: iCloudURL.path) {
            try FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)
            
            // Wait for download to complete (with timeout)
            var attempts = 0
            let maxAttempts = 50 // 5 seconds
            
            while attempts < maxAttempts && !FileManager.default.fileExists(atPath: iCloudURL.path) {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                attempts += 1
            }
            
            if attempts >= maxAttempts {
                throw SyncError.downloadFailed
            }
        }
        
        // Copy to local cache
        try FileManager.default.copyItem(at: iCloudURL, to: localURL)
        return localURL
    }
    
    // MARK: - Utilities
    
    private func iCloudDocumentsDirectory() throws -> URL {
        guard let url = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.speccy.documents") else {
            throw SyncError.iCloudUnavailable
        }
        return url.appendingPathComponent("Documents")
    }
    
    private func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("tts-cache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

// MARK: - Error Types

enum SyncError: Error, LocalizedError {
    case iCloudUnavailable
    case notConfigured
    case uploadFailed
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not available"
        case .notConfigured:
            return "Sync manager not configured"
        case .uploadFailed:
            return "Failed to upload file"
        case .downloadFailed:
            return "Failed to download file"
        }
    }
}

// MARK: - AppLogger Extension

extension AppLogger.Category {
    static let sync = AppLogger.Category.system // Use existing category for now
}
