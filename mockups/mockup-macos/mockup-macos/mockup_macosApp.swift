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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1200, height: 800)
    }
}

/// Configures the hosting window for transparent titlebar with inline traffic lights
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        // Use async to ensure window exists
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            // Allow content to extend behind titlebar
            window.styleMask.insert(.fullSizeContentView)

            // Make titlebar completely transparent
            window.titlebarAppearsTransparent = true

            // Hide title text
            window.titleVisibility = .hidden

            // Remove toolbar to minimize titlebar height
            window.toolbar = nil
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
