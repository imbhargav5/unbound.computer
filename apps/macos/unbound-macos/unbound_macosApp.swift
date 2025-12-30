//
//  unbound_macosApp.swift
//  unbound-macos
//
//  Main app entry with shadcn design system
//

import SwiftUI

@main
struct unbound_macosApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.themeColors, ThemeColors(appState.themeMode.colorScheme ?? .dark))
                .preferredColorScheme(appState.themeMode.colorScheme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

        // Settings window
        Settings {
            SettingsView()
                .environment(appState)
                .environment(\.themeColors, ThemeColors(appState.themeMode.colorScheme ?? .dark))
                .preferredColorScheme(appState.themeMode.colorScheme)
        }
    }
}
