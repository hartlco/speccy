import Foundation
import SwiftUI
import Combine
import UIKit

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
    private var speechService: SpeechService
    private var activeDownloads: [String: Task<Void, Never>] = [:]
    
    private init() {
        self.speechService = SpeechService()
        
        // Set up background task handling for downloads
        setupBackgroundTaskSupport()
    }
    
    private func setupBackgroundTaskSupport() {
        // Observe app state changes to handle background downloads
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppEnterBackground()
        }
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
                            AppLogger.shared.info("Download completed for '\(download.title)'", category: .download)
                        case .failure(let error):
                            self.downloads[index].state = .failed(error)
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