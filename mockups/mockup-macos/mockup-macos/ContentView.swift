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

    /// Commands available in the command palette
    private var commands: [CommandItem] {
        [
            CommandItem(
                icon: "folder.badge.plus",
                title: "Add Repository",
                shortcut: "⌘⇧A"
            ) {
                appState.showAddRepository = true
            },
        ]
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

            // Command Palette overlay
            if appState.showCommandPalette {
                CommandPaletteOverlay(
                    isPresented: Binding(
                        get: { appState.showCommandPalette },
                        set: { appState.showCommandPalette = $0 }
                    ),
                    commands: commands
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(colors.background)
        .background(
            KeyboardShortcutHandler(
                key: "k",
                modifiers: .command
            ) {
                withAnimation(.easeOut(duration: Duration.fast)) {
                    appState.showCommandPalette.toggle()
                }
            }
        )
    }
}

// MARK: - Keyboard Shortcut Handler

struct KeyboardShortcutHandler: NSViewRepresentable {
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.key = key
        view.modifiers = modifiers
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyCaptureView {
            view.action = action
        }
    }

    class KeyCaptureView: NSView {
        var key: String = ""
        var modifiers: NSEvent.ModifierFlags = []
        var action: (() -> Void)?

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }

                    let eventModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                    let requiredModifiers = self.modifiers.intersection([.command, .shift, .option, .control])

                    if event.charactersIgnoringModifiers?.lowercased() == self.key.lowercased(),
                       eventModifiers == requiredModifiers
                    {
                        self.action?()
                        return nil // Consume the event
                    }
                    return event
                }
            }
        }

        override func removeFromSuperview() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}

#Preview {
    ContentView()
        .environment(MockAppState())
        .frame(width: 1200, height: 800)
}
