//
//  SwiftTerminalView.swift
//  unbound-macos
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
        let colors = ThemeColors(colorScheme)
        SwiftTerminalWrapper(
            workingDirectory: workingDirectory,
            colorScheme: colorScheme
        )
        .background(colors.chatBackground)
    }
}

// MARK: - SwiftTerm NSView Wrapper

struct SwiftTerminalWrapper: NSViewRepresentable {
    let workingDirectory: String
    let colorScheme: ColorScheme

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

        let foregroundHex = colorScheme == .dark ? "E5E5E5" : "0D0D0D"
        let backgroundHex = colorScheme == .dark ? "0F0F0F" : "FFFFFF"

        terminal.nativeForegroundColor = NSColor(hex: foregroundHex)
        terminal.nativeBackgroundColor = NSColor(hex: backgroundHex)
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

private extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
