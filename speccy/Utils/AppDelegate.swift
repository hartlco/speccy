//
//  AppDelegate.swift
//  speccy
//
//  Created by Claude Code on 26.08.25.
//

#if canImport(UIKit)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Store the completion handler to call when background downloads finish
        BackgroundSessionManager.shared.setCompletionHandler(completionHandler, for: identifier)
    }
}

class BackgroundSessionManager {
    static let shared = BackgroundSessionManager()
    private var completionHandlers: [String: () -> Void] = [:]
    
    private init() {}
    
    func setCompletionHandler(_ handler: @escaping () -> Void, for identifier: String) {
        completionHandlers[identifier] = handler
    }
    
    func callCompletionHandler(for identifier: String) {
        completionHandlers[identifier]?()
        completionHandlers.removeValue(forKey: identifier)
    }
}
#else
// macOS fallback implementation
class BackgroundSessionManager {
    static let shared = BackgroundSessionManager()
    
    private init() {}
    
    func setCompletionHandler(_ handler: @escaping () -> Void, for identifier: String) {
        // No-op on macOS
    }
    
    func callCompletionHandler(for identifier: String) {
        // No-op on macOS
    }
}
#endif