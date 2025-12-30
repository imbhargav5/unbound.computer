//
//  ContentView.swift
//  rocketry-macos
//
//  Main content view with shadcn styling
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Group {
            if appState.showSettings {
                SettingsView()
                    .transition(.move(edge: .trailing))
            } else {
                WorkspaceView()
                    .transition(.move(edge: .leading))
            }
        }
        .background(colors.background)
        .animation(.easeInOut(duration: Duration.default), value: appState.showSettings)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}
