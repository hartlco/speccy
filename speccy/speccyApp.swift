//
//  speccyApp.swift
//  speccy
//
//  Created by Martin Hartl on 23.08.25.
//

import SwiftUI
import SwiftData
import CloudKit

@main
struct speccyApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([SpeechDocument.self, TTSAudioFile.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema, 
            isStoredInMemoryOnly: false, 
            cloudKitDatabase: .private("iCloud.co.hartl.speccy")
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // More detailed error handling for debugging
            print("Failed to create ModelContainer: \(error)")
            let nsError = error as NSError
            print("Error domain: \(nsError.domain)")
            print("Error code: \(nsError.code)")
            print("Error userInfo: \(nsError.userInfo)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Configure services once the container is ready
                    SpeechService.shared.configure(with: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
