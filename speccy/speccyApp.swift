//
//  speccyApp.swift
//  speccy
//
//  Created by Martin Hartl on 23.08.25.
//

import SwiftUI
import SwiftData

@main
struct speccyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SpeechDocument.self)
    }
}
