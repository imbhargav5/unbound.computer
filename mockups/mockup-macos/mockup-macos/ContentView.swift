//
//  ContentView.swift
//  mockup-macos
//
//  Main content view that routes to WorkspaceView
//

import SwiftUI

struct ContentView: View {
    @Environment(MockAppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ZStack {
            // Main workspace view
            WorkspaceView()

            // Settings overlay (if needed in future)
            if appState.showSettings {
                // Settings view would go here
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        appState.showSettings = false
                    }

                VStack {
                    Text("Settings")
                        .font(Typography.h2)
                        .foregroundStyle(colors.foreground)

                    Button("Close") {
                        appState.showSettings = false
                    }
                    .buttonPrimary()
                }
                .padding(Spacing.xxl)
                .background(colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(colors.background)
    }
}

#Preview {
    ContentView()
        .environment(MockAppState())
        .frame(width: 1200, height: 800)
}
