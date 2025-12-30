//
//  SwiftTerminalView.swift
//  rocketry-macos
//
//  Terminal view using SwiftTerm for proper VT100/xterm emulation
//

import SwiftUI
import SwiftTerm

// MARK: - Terminal Container

struct TerminalContainer: View {
    @Environment(\.colorScheme) private var colorScheme

    let workingDirectory: String

    var body: some View {
        SwiftTerminalWrapper(
            workingDirectory: workingDirectory,
            isDarkMode: colorScheme == .dark
        )
        .background(colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
    }
}

// MARK: - SwiftTerm NSView Wrapper

struct SwiftTerminalWrapper: NSViewRepresentable {
    let workingDirectory: String
    let isDarkMode: Bool

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)

        // Configure terminal appearance
        configureTerminalAppearance(terminal)

        // Start shell process with environment
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let environment = buildEnvironment()
        terminal.startProcess(executable: shell, args: [], environment: environment, execName: nil)

        // Change to working directory after a brief delay to let shell initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            terminal.send(txt: "cd \"\(workingDirectory)\" && clear\n")
        }

        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        // Update colors if theme changed
        configureTerminalAppearance(terminal)
    }

    private func configureTerminalAppearance(_ terminal: LocalProcessTerminalView) {
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        if isDarkMode {
            terminal.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
            terminal.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        } else {
            terminal.nativeForegroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            terminal.nativeBackgroundColor = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        }
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"

        return env.map { "\($0.key)=\($0.value)" }
    }
}

#Preview {
    TerminalContainer(workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        .frame(width: 600, height: 400)
}
