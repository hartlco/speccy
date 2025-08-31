import Foundation
import SwiftUI
import Combine

@MainActor
class DownloadManagerBackend: ObservableObject {
    static let shared = DownloadManagerBackend()
    
    enum DownloadState {
        case pending
        case downloading(progress: Double)
        case completed
        case failed(Error)
        case cancelled
    }
    
    struct DownloadItem: Identifiable {
        let id: String
        let documentId: String
        let title: String
        let text: String
        var state: DownloadState
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
    private var speechService: SpeechServiceBackend
    private var activeDownloads: [String: Task<Void, Never>] = [:]
    
    private init() {
        self.speechService = SpeechServiceBackend.shared
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
            createdAt: Date()
        )
        
        downloads.append(downloadItem)
        
        // Start the download task
        let downloadTask = Task {
            await performDownload(downloadId: downloadId, text: text, title: title)
        }
        
        activeDownloads[downloadId] = downloadTask
    }
    
    private func performDownload(downloadId: String, text: String, title: String) async {
        guard let index = downloads.firstIndex(where: { $0.id == downloadId }) else {
            return
        }
        
        // Update state to downloading
        downloads[index].state = .downloading(progress: 0.0)
        
        // Use speechService to preload audio
        speechService.preloadAudio(text: text, onProgress: { [weak self] progress in
            Task { @MainActor in
                guard let self = self,
                      let currentIndex = self.downloads.firstIndex(where: { $0.id == downloadId }) else {
                    return
                }
                self.downloads[currentIndex].state = .downloading(progress: progress)
            }
        }, onCompletion: { [weak self] result in
            Task { @MainActor in
                guard let self = self,
                      let currentIndex = self.downloads.firstIndex(where: { $0.id == downloadId }) else {
                    return
                }
                
                switch result {
                case .success:
                    self.downloads[currentIndex].state = .completed
                    AppLogger.shared.info("Download completed for '\(title)'", category: .download)
                case .failure(let error):
                    self.downloads[currentIndex].state = .failed(error)
                    AppLogger.shared.error("Download failed for '\(title)': \(error.localizedDescription)", category: .download)
                }
                
                // Clean up the active download
                self.activeDownloads.removeValue(forKey: downloadId)
            }
        })
    }
    
    func cancelDownload(for documentId: String) {
        // Find and cancel active downloads for this document
        let itemsToCancel = downloads.filter { $0.documentId == documentId && $0.isActive }
        
        for item in itemsToCancel {
            activeDownloads[item.id]?.cancel()
            activeDownloads.removeValue(forKey: item.id)
            
            if let index = downloads.firstIndex(where: { $0.id == item.id }) {
                downloads[index].state = .cancelled
            }
        }
        
        AppLogger.shared.info("Cancelled downloads for document: \(documentId)", category: .download)
    }
    
    func removeDownload(downloadId: String) {
        downloads.removeAll { $0.id == downloadId }
        activeDownloads[downloadId]?.cancel()
        activeDownloads.removeValue(forKey: downloadId)
    }
    
    func retryDownload(downloadId: String) {
        // Find the download item and restart it
        if let downloadIndex = downloads.firstIndex(where: { $0.id == downloadId }) {
            let download = downloads[downloadIndex]
            downloads[downloadIndex].state = .pending
            startDownload(for: download.documentId, title: download.title, text: download.text)
        }
    }
    
    func clearCompletedDownloads() {
        downloads.removeAll { 
            if case .completed = $0.state {
                return true
            }
            return false
        }
    }
    
    // MARK: - Status Queries
    
    var activeDownloadsCount: Int {
        return downloads.filter { $0.isActive }.count
    }
    
    var hasActiveDownloads: Bool {
        return activeDownloadsCount > 0
    }
    
    func downloadState(for documentId: String) -> DownloadState? {
        return downloads.first { $0.documentId == documentId }?.state
    }
    
    func isDownloading(documentId: String) -> Bool {
        return downloads.contains { $0.documentId == documentId && $0.isActive }
    }
    
    func checkCacheStatus(for documentId: String, text: String) -> Bool {
        return speechService.isAudioCached(for: text)
    }

    // MARK: - Compatibility methods for existing UI
    
    func checkSyncAvailability(for documentId: String, text: String) {
        // With backend service, sync is automatic - no need for separate sync availability check
        AppLogger.shared.info("Sync availability check not needed with backend service", category: .system)
    }
    
    func refreshAllSyncStates() {
        // No-op with backend service
        AppLogger.shared.info("Sync state refresh not needed with backend service", category: .system)
    }
    
    func getDownloadState(for documentId: String) -> DownloadState? {
        return downloadState(for: documentId)
    }
    
    enum SyncState {
        case notSynced // For compatibility with existing UI
        case syncing // For compatibility with existing UI
        case synced // Backend service is always "synced"
        case syncFailed(Error) // For compatibility with existing UI
    }
    
    func getSyncState(for documentId: String) -> SyncState? {
        return .synced // Backend service handles sync automatically
    }
    
    func isAudioCached(for documentId: String, text: String) -> Bool {
        return speechService.isAudioCached(for: text)
    }
    
    func updateSyncState(for documentId: String, to state: SyncState) {
        // No-op with backend service - sync is automatic
    }
}