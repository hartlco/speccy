import Foundation
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    enum DownloadState {
        case pending
        case downloading(progress: Double)
        case completed
        case failed(Error)
        case cancelled
    }
    
    enum SyncState {
        case notSynced
        case syncing
        case synced
        case availableInCloud // File exists in iCloud but not locally
        case iCloudUnavailable // iCloud is not available (not signed in, container issues, etc.)
        case syncFailed(Error)
    }
    
    struct DownloadItem: Identifiable {
        let id: String
        let documentId: String
        let title: String
        let text: String
        var state: DownloadState
        var syncState: SyncState
        let createdAt: Date
        
        var isActive: Bool {
            switch state {
            case .pending, .downloading:
                return true
            case .completed, .failed, .cancelled:
                return false
            }
        }
    }
    
    @Published private(set) var downloads: [DownloadItem] = []
    private var speechService: SpeechService
    private var activeDownloads: [String: Task<Void, Never>] = [:]
    
    private init() {
        self.speechService = SpeechService.shared
        
        // Set up background task handling for downloads
        setupBackgroundTaskSupport()
    }
    
    private func setupBackgroundTaskSupport() {
        // Observe app state changes to handle background downloads
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppEnterBackground()
        }
        #endif
    }
    
    private func handleAppEnterBackground() {
        AppLogger.shared.info("App entering background with \(activeDownloadsCount) active downloads", category: .download)
        
        // Background downloads will continue automatically with URLSessionConfiguration.background
        // No additional action needed as the system handles background downloads
    }
    
    func startDownload(for documentId: String, title: String, text: String) {
        let downloadId = "\(documentId)_\(Date().timeIntervalSince1970)"
        
        AppLogger.shared.info("Starting download for '\(title)' (docId: \(documentId))", category: .download)
        
        // Cancel any existing download for this document
        cancelDownload(for: documentId)
        
        // Remove any old downloads for this document
        downloads.removeAll { $0.documentId == documentId }
        
        // Create new download item
        let downloadItem = DownloadItem(
            id: downloadId,
            documentId: documentId,
            title: title,
            text: text,
            state: .pending,
            syncState: .notSynced,
            createdAt: Date()
        )
        
        downloads.append(downloadItem)
        
        // Start the download task
        let task = Task { @MainActor in
            await performDownload(downloadId: downloadId, text: text)
        }
        
        activeDownloads[downloadId] = task
    }
    
    func cancelDownload(for documentId: String) {
        // Find and cancel active downloads for this document
        if let downloadItem = downloads.first(where: { $0.documentId == documentId && $0.isActive }) {
            AppLogger.shared.info("Cancelling download for '\(downloadItem.title)'", category: .download)
            activeDownloads[downloadItem.id]?.cancel()
            activeDownloads.removeValue(forKey: downloadItem.id)
            
            if let index = downloads.firstIndex(where: { $0.id == downloadItem.id }) {
                downloads[index].state = .cancelled
            }
        }
    }
    
    func retryDownload(_ downloadId: String) {
        guard let index = downloads.firstIndex(where: { $0.id == downloadId }) else { return }
        let download = downloads[index]
        
        downloads[index].state = .pending
        
        let task = Task { @MainActor in
            await performDownload(downloadId: downloadId, text: download.text)
        }
        
        activeDownloads[downloadId] = task
    }
    
    func removeDownload(_ downloadId: String) {
        // Cancel if active
        activeDownloads[downloadId]?.cancel()
        activeDownloads.removeValue(forKey: downloadId)
        
        // Remove from list
        downloads.removeAll { $0.id == downloadId }
    }
    
    func getDownloadState(for documentId: String) -> DownloadState? {
        return downloads.first { $0.documentId == documentId }?.state
    }
    
    func isAudioCached(for documentId: String, text: String) -> Bool {
        // Check if there's a completed download
        if let download = downloads.first(where: { $0.documentId == documentId && $0.text == text }) {
            if case .completed = download.state {
                return true
            }
        }
        
        // Check physical cache
        return speechService.isAudioCached(for: text)
    }
    
    func getSyncState(for documentId: String) -> SyncState? {
        return downloads.first { $0.documentId == documentId }?.syncState
    }
    
    func updateSyncState(for documentId: String, to newState: SyncState) {
        if let index = downloads.firstIndex(where: { $0.documentId == documentId }) {
            downloads[index].syncState = newState
            AppLogger.shared.info("Updated sync state for \(downloads[index].title) to: \(newState)", category: .sync)
        }
    }
    
    func checkSyncAvailability(for documentId: String, text: String) {
        Task {
            // If iCloud is not available, set appropriate state
            guard iCloudSyncManager.shared.iCloudAvailable else {
                await MainActor.run {
                    updateSyncState(for: documentId, to: .iCloudUnavailable)
                }
                return
            }
            
            AppLogger.shared.info("Checking sync availability for document: \(documentId)", category: .sync)
            
            // Check if audio is available in iCloud (this now checks both database and physical files)
            let isAvailableInSync = await speechService.isAudioAvailableInSync(for: text)
            let isCachedLocally = speechService.isAudioCached(for: text)
            
            AppLogger.shared.info("Sync check results - isAvailableInSync: \(isAvailableInSync), isCachedLocally: \(isCachedLocally)", category: .sync)
            
            await MainActor.run {
                if isAvailableInSync && !isCachedLocally {
                    AppLogger.shared.info("Setting sync state to availableInCloud", category: .sync)
                    updateSyncState(for: documentId, to: .availableInCloud)
                } else if isAvailableInSync && isCachedLocally {
                    AppLogger.shared.info("Setting sync state to synced", category: .sync)
                    updateSyncState(for: documentId, to: .synced)
                } else {
                    AppLogger.shared.info("Setting sync state to notSynced", category: .sync)
                    updateSyncState(for: documentId, to: .notSynced)
                }
            }
        }
    }
    
    // Refresh sync state for all downloads - useful when app becomes active
    func refreshAllSyncStates() {
        AppLogger.shared.info("Refreshing sync states for all downloads", category: .sync)
        for download in downloads {
            checkSyncAvailability(for: download.documentId, text: download.text)
        }
    }
    
    private func syncToiCloud(downloadId: String, text: String) {
        guard let index = downloads.firstIndex(where: { $0.id == downloadId }) else { return }
        let download = downloads[index]
        
        Task {
            // Check if iCloud is available
            guard iCloudSyncManager.shared.iCloudAvailable else {
                AppLogger.shared.info("iCloud not available, skipping sync for '\(download.title)'", category: .sync)
                await MainActor.run {
                    self.downloads[index].syncState = .iCloudUnavailable
                }
                return
            }
            
            guard let config = speechService.loadOpenAIConfig() else {
                await MainActor.run {
                    self.downloads[index].syncState = .syncFailed(NSError(domain: "DownloadManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI config"]))
                }
                return
            }
            
            do {
                let parts = speechService.chunkText(text)
                
                // Sync each chunk to iCloud
                for part in parts {
                    let key = speechService.cacheKey(text: part, model: config.model, voice: config.voice, format: config.format)
                    let localURL = speechService.ensureCacheFileURL(forKey: key, format: config.format)
                    
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        let contentHash = TTSAudioFile.contentHash(for: part, model: config.model, voice: config.voice, format: config.format)
                        
                        try await iCloudSyncManager.shared.syncAudioFileToiCloud(
                            localURL: localURL,
                            contentHash: contentHash,
                            model: config.model,
                            voice: config.voice,
                            format: config.format
                        )
                    }
                }
                
                await MainActor.run {
                    if let currentIndex = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[currentIndex].syncState = .synced
                        AppLogger.shared.info("Successfully synced '\(download.title)' to iCloud", category: .sync)
                    }
                }
                
            } catch {
                await MainActor.run {
                    if let currentIndex = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[currentIndex].syncState = .syncFailed(error)
                        AppLogger.shared.error("Failed to sync '\(download.title)' to iCloud: \(error.localizedDescription)", category: .sync)
                    }
                }
            }
        }
    }
    
    private func performDownload(downloadId: String, text: String) async {
        guard let index = downloads.firstIndex(where: { $0.id == downloadId }) else { return }
        
        let download = downloads[index]
        AppLogger.shared.info("Starting download execution for '\(download.title)'", category: .download)
        
        downloads[index].state = .downloading(progress: 0.0)
        
        await withCheckedContinuation { continuation in
            speechService.preloadAudio(
                text: text,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self = self,
                              let index = self.downloads.firstIndex(where: { $0.id == downloadId }) else { return }
                        self.downloads[index].state = .downloading(progress: progress)
                    }
                },
                onCompletion: { [weak self] result in
                    Task { @MainActor in
                        guard let self = self,
                              let index = self.downloads.firstIndex(where: { $0.id == downloadId }) else { 
                            continuation.resume()
                            return 
                        }
                        
                        let download = self.downloads[index]
                        switch result {
                        case .success:
                            self.downloads[index].state = .completed
                            self.downloads[index].syncState = .syncing // Will start syncing to iCloud
                            AppLogger.shared.info("Download completed for '\(download.title)'", category: .download)
                            
                            // Start syncing to iCloud
                            self.syncToiCloud(downloadId: downloadId, text: download.text)
                            
                        case .failure(let error):
                            self.downloads[index].state = .failed(error)
                            self.downloads[index].syncState = .syncFailed(error)
                            AppLogger.shared.error("Download failed for '\(download.title)': \(error.localizedDescription)", category: .download)
                        }
                        
                        self.activeDownloads.removeValue(forKey: downloadId)
                        continuation.resume()
                    }
                }
            )
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupOldDownloads() {
        let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        downloads.removeAll { download in
            !download.isActive && download.createdAt < oneWeekAgo
        }
    }
    
    // MARK: - Computed Properties
    
    var activeDownloadsCount: Int {
        downloads.filter { $0.isActive }.count
    }
    
    var hasActiveDownloads: Bool {
        downloads.contains { $0.isActive }
    }
}