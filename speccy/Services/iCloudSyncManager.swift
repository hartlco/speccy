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
        AppLogger.shared.info("Initializing iCloudSyncManager...", category: .sync)
        
        // Debug app configuration
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        AppLogger.shared.info("Bundle ID: \(bundleId)", category: .sync)
        AppLogger.shared.info("Running on: \(ProcessInfo.processInfo.operatingSystemVersionString)", category: .sync)
        
        // Debug iCloud availability step by step
        if let ubiquityToken = FileManager.default.ubiquityIdentityToken {
            AppLogger.shared.info("✅ User is signed into iCloud (token: \(ubiquityToken.description.prefix(20))...)", category: .sync)
        } else {
            AppLogger.shared.error("❌ User is NOT signed into iCloud", category: .sync)
        }
        
        // Test direct container URL access - use the working container ID
        let containerId = "iCloud.co.hartl.speccy"
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId) {
            AppLogger.shared.info("✅ Container URL accessible: \(containerURL.path)", category: .sync)
        } else {
            AppLogger.shared.error("❌ Cannot get container URL for: \(containerId)", category: .sync)
            AppLogger.shared.info("Possible issues:", category: .sync)
            AppLogger.shared.info("1. Container not configured in Apple Developer Portal", category: .sync)
            AppLogger.shared.info("2. App ID doesn't match bundle identifier", category: .sync)
            AppLogger.shared.info("3. iCloud Drive is disabled", category: .sync)
            AppLogger.shared.info("4. Running in simulator without proper entitlements", category: .sync)
        }
        
        self.container = CKContainer(identifier: containerId)
        self.privateDatabase = container.privateCloudDatabase
        checkiCloudStatus()
        
        // Run debug check
        debugContainerAccess()
    }
    
    // Debug function to test different container identifiers
    func debugContainerAccess() {
        AppLogger.shared.info("=== DEBUGGING ICLOUD CONTAINER ACCESS ===", category: .sync)
        
        let testContainers = [
            "iCloud.co.hartl.speccy",
            "iCloud.com.speccy.documents", 
            "iCloud.\(Bundle.main.bundleIdentifier ?? "unknown")",
            nil // Default container
        ]
        
        for container in testContainers {
            let containerName = container ?? "default"
            AppLogger.shared.info("Testing container: \(containerName)", category: .sync)
            
            if let url = FileManager.default.url(forUbiquityContainerIdentifier: container) {
                AppLogger.shared.info("✅ SUCCESS: \(containerName) -> \(url.path)", category: .sync)
            } else {
                AppLogger.shared.error("❌ FAILED: \(containerName) not accessible", category: .sync)
            }
        }
        
        AppLogger.shared.info("=== END CONTAINER DEBUG ===", category: .sync)
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
        guard iCloudAvailable else { 
            AppLogger.shared.error("Cannot sync to iCloud: iCloud unavailable", category: .sync)
            throw SyncError.iCloudUnavailable 
        }
        guard let modelContext = modelContext else { 
            AppLogger.shared.error("Cannot sync to iCloud: sync manager not configured", category: .sync)
            throw SyncError.notConfigured 
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
        syncStatus = .syncing
        AppLogger.shared.info("Starting iCloud sync for audio file with hash: \(contentHash) (size: \(fileSize) bytes)", category: .sync)
        
        do {
            // First check if this file already exists in CloudKit
            AppLogger.shared.info("Checking if audio file already exists in iCloud for hash: \(contentHash.prefix(8))", category: .sync)
            if try await audioFileExists(contentHash: contentHash) {
                AppLogger.shared.info("Audio file already exists in iCloud, skipping upload for hash: \(contentHash.prefix(8))", category: .sync)
                syncStatus = .idle
                return
            } else {
                AppLogger.shared.info("Audio file does NOT exist in iCloud, proceeding with upload for hash: \(contentHash.prefix(8))", category: .sync)
            }
            
            // Upload to iCloud Documents
            AppLogger.shared.info("Uploading audio file to iCloud Documents...", category: .sync)
            let iCloudURL = try await uploadAudioFile(localURL: localURL, filename: "\(contentHash).\(format)")
            AppLogger.shared.info("Successfully uploaded to iCloud at: \(iCloudURL.path)", category: .sync)
            
            // Check if record already exists (since we can't use unique constraints with CloudKit)
            AppLogger.shared.info("Checking for existing database record...", category: .sync)
            let predicate = #Predicate<TTSAudioFile> { $0.contentHash == contentHash }
            let descriptor = FetchDescriptor<TTSAudioFile>(predicate: predicate)
            let existingFiles = try modelContext.fetch(descriptor)
            
            if existingFiles.isEmpty {
                // Create new database record
                AppLogger.shared.info("Creating new database record for audio file", category: .sync)
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
                AppLogger.shared.info("Database record created successfully", category: .sync)
            } else {
                // Update existing record with iCloud URL if needed
                if let existingFile = existingFiles.first, existingFile.iCloudURL != iCloudURL {
                    AppLogger.shared.info("Updating existing database record with new iCloud URL", category: .sync)
                    existingFile.iCloudURL = iCloudURL
                    try modelContext.save()
                } else {
                    AppLogger.shared.info("Database record already up to date", category: .sync)
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
        guard iCloudAvailable else { 
            AppLogger.shared.error("Cannot download from iCloud: iCloud unavailable", category: .sync)
            throw SyncError.iCloudUnavailable 
        }
        guard let modelContext = modelContext else { 
            AppLogger.shared.error("Cannot download from iCloud: sync manager not configured", category: .sync)
            throw SyncError.notConfigured 
        }
        
        AppLogger.shared.info("Searching for audio file in sync database with hash: \(contentHash)", category: .sync)
        
        // Check if we have this audio file record
        let predicate = #Predicate<TTSAudioFile> { $0.contentHash == contentHash }
        let descriptor = FetchDescriptor<TTSAudioFile>(predicate: predicate)
        
        let audioFile = try modelContext.fetch(descriptor).first
        
        var iCloudURL: URL?
        if let audioFile = audioFile, let storedURL = audioFile.iCloudURL {
            // Use stored iCloud URL
            iCloudURL = storedURL
            AppLogger.shared.info("Found audio file record with stored iCloud URL", category: .sync)
        } else if let audioFile = audioFile {
            // Construct iCloud URL from filename
            let iCloudFolderURL = try iCloudDocumentsDirectory().appendingPathComponent("AudioCache")
            iCloudURL = iCloudFolderURL.appendingPathComponent(audioFile.filename)
            AppLogger.shared.info("Found audio file record, constructed iCloud URL from filename: \(audioFile.filename)", category: .sync)
        } else {
            // Try to find the file by checking all possible formats
            let iCloudFolderURL = try iCloudDocumentsDirectory().appendingPathComponent("AudioCache")
            let formats = ["mp3", "aac", "wav"]
            for format in formats {
                let potentialURL = iCloudFolderURL.appendingPathComponent("\(contentHash).\(format)")
                if FileManager.default.fileExists(atPath: potentialURL.path) {
                    iCloudURL = potentialURL
                    AppLogger.shared.info("Found orphaned file in iCloud: \(potentialURL.lastPathComponent)", category: .sync)
                    break
                }
            }
            
            if iCloudURL == nil {
                AppLogger.shared.info("No audio file found in sync database or iCloud for hash: \(contentHash)", category: .sync)
                return nil
            }
        }
        
        guard let finalURL = iCloudURL else {
            AppLogger.shared.info("Unable to determine iCloud URL for hash: \(contentHash)", category: .sync)
            return nil
        }
        
        AppLogger.shared.info("Attempting download from iCloud URL: \(finalURL.path)", category: .sync)
        
        // Download from iCloud Documents to local cache  
        let filename = audioFile?.filename ?? finalURL.lastPathComponent
        let localCacheURL = cacheDirectory().appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: localCacheURL.path) {
            AppLogger.shared.info("Audio file already exists in local cache", category: .sync)
            return localCacheURL
        }
        
        AppLogger.shared.info("Starting download from iCloud to local cache...", category: .sync)
        let downloadedURL = try await downloadFile(from: finalURL, to: localCacheURL)
        AppLogger.shared.info("Successfully downloaded audio file from iCloud", category: .sync)
        return downloadedURL
    }
    
    func audioFileExists(contentHash: String) async throws -> Bool {
        guard let modelContext = modelContext else { 
            AppLogger.shared.warning("ModelContext not available for audioFileExists check", category: .sync)
            return false 
        }
        
        // First check local database
        let predicate = #Predicate<TTSAudioFile> { $0.contentHash == contentHash }
        let descriptor = FetchDescriptor<TTSAudioFile>(predicate: predicate)
        
        let results = try modelContext.fetch(descriptor)
        
        if !results.isEmpty {
            AppLogger.shared.info("Audio file found in local database for hash: \(contentHash.prefix(8))", category: .sync)
            return true
        }
        
        AppLogger.shared.info("Audio file NOT found in local database for hash: \(contentHash.prefix(8)), checking physical iCloud files...", category: .sync)
        
        // If not in local database, check if the physical file exists in iCloud
        // This handles the case where another device uploaded the file
        do {
            let iCloudURL = try iCloudDocumentsDirectory()
            let audioFolderURL = iCloudURL.appendingPathComponent("AudioCache")
            
            // Try different formats that might exist
            let formats = ["mp3", "aac", "wav"]
            for format in formats {
                let filename = "\(contentHash).\(format)"
                let fileURL = audioFolderURL.appendingPathComponent(filename)
                
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    AppLogger.shared.info("Found orphaned iCloud file: \(filename), adding to database", category: .sync)
                    
                    // File exists but not in database - add it to database
                    let orphanedFile = TTSAudioFile(
                        contentHash: contentHash,
                        filename: filename,
                        fileSize: (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0,
                        model: "unknown", // We don't know the original model
                        voice: "unknown", // We don't know the original voice
                        format: format,
                        iCloudURL: fileURL
                    )
                    
                    modelContext.insert(orphanedFile)
                    try modelContext.save()
                    
                    return true
                }
            }
        } catch {
            AppLogger.shared.error("Error checking for physical iCloud files: \(error.localizedDescription)", category: .sync)
        }
        
        AppLogger.shared.info("Audio file not found anywhere for hash: \(contentHash.prefix(8))", category: .sync)
        return false
    }
    
    private func uploadAudioFile(localURL: URL, filename: String) async throws -> URL {
        AppLogger.shared.info("Getting iCloud Documents directory...", category: .sync)
        let iCloudDocumentsURL = try iCloudDocumentsDirectory()
        let destinationURL = iCloudDocumentsURL.appendingPathComponent("AudioCache").appendingPathComponent(filename)
        
        AppLogger.shared.info("Target iCloud location: \(destinationURL.path)", category: .sync)
        
        // Ensure directory exists
        let cacheDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            AppLogger.shared.info("Creating iCloud AudioCache directory", category: .sync)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        // Copy file to iCloud Documents
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            AppLogger.shared.info("Removing existing file at destination", category: .sync)
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        AppLogger.shared.info("Copying file from local to iCloud Documents", category: .sync)
        try FileManager.default.copyItem(at: localURL, to: destinationURL)
        
        // Set file permissions to ensure cross-platform access
        AppLogger.shared.info("Setting file permissions for cross-platform access", category: .sync)
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o644  // Read/write for owner, read for group/others
        ]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: destinationURL.path)
        AppLogger.shared.info("File permissions set successfully", category: .sync)
        
        AppLogger.shared.info("File copy completed successfully", category: .sync)
        
        return destinationURL
    }
    
    private func downloadFile(from iCloudURL: URL, to localURL: URL) async throws -> URL {
        AppLogger.shared.info("Starting iCloud file download from: \(iCloudURL.path)", category: .sync)
        
        // Ensure local directory exists
        let localDir = localURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: localDir.path) {
            AppLogger.shared.info("Creating local cache directory", category: .sync)
            try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        }
        
        // Use file coordination for safe iCloud access
        let fileCoordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var downloadError: Error?
        
        fileCoordinator.coordinate(readingItemAt: iCloudURL, options: [], error: &coordinatorError) { (readingURL) in
            do {
                AppLogger.shared.info("File coordinator - checking file accessibility", category: .sync)
                
                // Check if file needs to be downloaded from iCloud
                var isDownloaded: AnyObject?
                try (readingURL as NSURL).getResourceValue(&isDownloaded, forKey: .ubiquitousItemDownloadingStatusKey)
                
                AppLogger.shared.info("Checking if iCloud file needs to be downloaded...", category: .sync)
                
                // Simple approach: if the file doesn't exist locally, try to download it
                if !FileManager.default.fileExists(atPath: readingURL.path) {
                    AppLogger.shared.info("File not available locally, starting iCloud download...", category: .sync)
                    try FileManager.default.startDownloadingUbiquitousItem(at: readingURL)
                    
                    // Wait for download to complete (with timeout)
                    var attempts = 0
                    let maxAttempts = 50 // 5 seconds
                    
                    AppLogger.shared.info("Waiting for iCloud download to complete...", category: .sync)
                    while attempts < maxAttempts && !FileManager.default.fileExists(atPath: readingURL.path) {
                        Thread.sleep(forTimeInterval: 0.1)
                        attempts += 1
                    }
                    
                    if attempts >= maxAttempts {
                        AppLogger.shared.error("iCloud download timed out after 5 seconds", category: .sync)
                        throw SyncError.downloadFailed
                    }
                    
                    AppLogger.shared.info("iCloud download completed after \(attempts * 100)ms", category: .sync)
                } else {
                    AppLogger.shared.info("File already available locally in iCloud Documents", category: .sync)
                }
                
                // Copy to local cache
                AppLogger.shared.info("Copying from iCloud Documents to local cache", category: .sync)
                try FileManager.default.copyItem(at: readingURL, to: localURL)
                AppLogger.shared.info("File successfully copied to local cache", category: .sync)
            } catch {
                AppLogger.shared.error("File coordinator error during download: \(error.localizedDescription)", category: .sync)
                downloadError = error
            }
        }
        
        // Check for coordination errors
        if let coordinatorError = coordinatorError {
            AppLogger.shared.error("File coordinator failed: \(coordinatorError.localizedDescription)", category: .sync)
            throw coordinatorError
        }
        
        // Check for download errors
        if let downloadError = downloadError {
            throw downloadError
        }
        
        return localURL
    }
    
    // MARK: - Utilities
    
    private func iCloudDocumentsDirectory() throws -> URL {
        // First check if user is signed in
        guard FileManager.default.ubiquityIdentityToken != nil else {
            AppLogger.shared.error("iCloud unavailable: User not signed into iCloud", category: .sync)
            throw SyncError.iCloudUnavailable
        }
        
        // Check if container is accessible
        guard let url = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.co.hartl.speccy") else {
            AppLogger.shared.error("Failed to get iCloud container URL for identifier 'iCloud.co.hartl.speccy'", category: .sync)
            AppLogger.shared.info("Possible causes: 1) Container not configured in Developer Portal 2) Entitlements missing 3) iCloud Drive disabled", category: .sync)
            throw SyncError.iCloudUnavailable
        }
        
        let documentsURL = url.appendingPathComponent("Documents")
        AppLogger.shared.info("iCloud Documents directory: \(documentsURL.path)", category: .sync)
        
        // Test if we can actually access the directory
        do {
            let resourceValues = try documentsURL.resourceValues(forKeys: [.isDirectoryKey])
            AppLogger.shared.info("iCloud Documents directory is accessible, isDirectory: \(resourceValues.isDirectory ?? false)", category: .sync)
        } catch {
            AppLogger.shared.warning("iCloud Documents directory may not be fully accessible: \(error.localizedDescription)", category: .sync)
        }
        
        return documentsURL
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
