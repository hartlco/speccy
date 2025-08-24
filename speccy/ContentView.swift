//
//  ContentView.swift
//  speccy
//
//  Created by Martin Hartl on 23.08.25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MiniPlayerContainer {
            DocumentListView()
        }
    }
}

#Preview {
    ContentView()
}
