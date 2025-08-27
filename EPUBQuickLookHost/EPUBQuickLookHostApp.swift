//
//  EPUBQuickLookHostApp.swift
//  EPUBQuickLookHost
//
//  Created by Aryan on 27/8/2025.
//

import SwiftUI

@main
struct EPUBQuickViewHostApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("EPUB Quick Look Host")
                .font(.title)
            Text("Build & run once to register the Quick Look extension.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 200)
        .padding()
    }
}
