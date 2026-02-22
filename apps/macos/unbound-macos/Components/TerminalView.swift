//
//  TerminalView.swift
//  unbound-macos
//
//  Real terminal view with command execution
//

import SwiftUI

struct TerminalView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var terminalState: TerminalState

    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(terminalState.lines) { line in
                            TerminalLineView(line: line, colors: colors)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                }
                .onChange(of: terminalState.lines.count) { _, _ in
                    if let lastLine = terminalState.lines.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastLine.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input area
            HStack(spacing: Spacing.xs) {
                // Prompt
                HStack(spacing: 2) {
                    Image(systemName: terminalState.isRunning ? "hourglass" : "chevron.right")
                        .font(.system(size: IconSize.xs, weight: .bold))
                        .foregroundStyle(terminalState.isRunning ? colors.warning : colors.success)

                    Text(terminalState.currentDirectoryName)
                        .font(Typography.terminal)
                        .foregroundStyle(colors.info)
                }

                TextField("", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(Typography.terminal)
                    .foregroundStyle(colors.foreground)
                    .focused($isInputFocused)
                    .disabled(terminalState.isRunning)
                    .onSubmit {
                        submitCommand()
                    }
                    .onKeyPress(.upArrow) {
                        if let prev = terminalState.getPreviousCommand() {
                            inputText = prev
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if let next = terminalState.getNextCommand() {
                            inputText = next
                        }
                        return .handled
                    }
                    .onKeyPress(characters: .init(charactersIn: "c")) { keyPress in
                        if keyPress.modifiers.contains(.control) && terminalState.isRunning {
                            terminalState.cancelCurrentProcess()
                            return .handled
                        }
                        return .ignored
                    }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(colors.card.opacity(0.5))
        }
        .background(colors.card)
        .onAppear {
            isInputFocused = true
        }
    }

    private func submitCommand() {
        let command = inputText
        inputText = ""

        Task {
            await terminalState.executeCommand(command)
        }
    }
}

// MARK: - Terminal Line View

struct TerminalLineView: View {
    let line: TerminalLine
    let colors: ThemeColors

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            switch line.type {
            case .command(let directory):
                // Command prompt
                HStack(spacing: 2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: IconSize.xs, weight: .bold))
                        .foregroundStyle(colors.success)

                    Text(directory)
                        .font(Typography.terminal)
                        .foregroundStyle(colors.info)
                }

                Text(line.content)
                    .font(Typography.terminal)
                    .foregroundStyle(colors.foreground)
                    .textSelection(.enabled)

            case .output:
                Text(line.content)
                    .font(Typography.terminal)
                    .foregroundStyle(colors.foreground)
                    .textSelection(.enabled)

            case .error:
                Text(line.content)
                    .font(Typography.terminal)
                    .foregroundStyle(colors.destructive)
                    .textSelection(.enabled)

            case .system:
                Text(line.content)
                    .font(Typography.terminal)
                    .foregroundStyle(colors.mutedForeground)
                    .italic()
            }

            Spacer(minLength: 0)
        }
    }
}

#if DEBUG

#Preview {
    TerminalView(terminalState: TerminalState(workingDirectory: "/Users/test/project"))
        .frame(width: 400, height: 200)
}

#endif
