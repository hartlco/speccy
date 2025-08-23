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
    var body: some Scene {
        WindowGroup {
            DocumentListView()
        }
        .modelContainer(for: SpeechDocument.self)
    }
}
