//
//  mockup_macosApp.swift
//  mockup-macos
//
//  Mockup app for testing and visualizing UI improvements
//  before porting them to the main macOS app.
//

import SwiftUI

@main
struct mockup_macosApp: App {
    @State private var appState = MockAppState()

    init() {
        // Register Geist fonts on app startup
        FontRegistration.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
    }
}
