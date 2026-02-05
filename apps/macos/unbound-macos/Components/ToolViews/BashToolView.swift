//
//  BashToolView.swift
//  unbound-macos
//
//  Terminal-style display for Bash tool execution
//

import SwiftUI

// MARK: - Bash Tool View

/// Terminal-style display with command prompt styling and scrollable output
struct BashToolView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    private var outputParser: ToolOutputParser {
        ToolOutputParser(toolUse.output)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ToolHeader(
                toolName: "Bash",
                status: toolUse.status,
                subtitle: parser.commandDescription ?? parser.command,
                icon: ToolIcon.icon(for: "Bash"),
                isExpanded: isExpanded,
                hasContent: parser.command != nil || toolUse.output != nil,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ShadcnDivider()

                    // Terminal content
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        // Command with prompt
                        if let command = parser.command {
                            HStack(alignment: .top, spacing: Spacing.xs) {
                                Text("$")
                                    .font(Typography.code)
                                    .foregroundStyle(colors.success)

                                Text(command)
                                    .font(Typography.code)
                                    .foregroundStyle(colors.foreground)
                                    .textSelection(.enabled)
                            }
                        }

                        // Output
                        if let output = toolUse.output, !output.isEmpty {
                            ScrollView {
                                Text(outputParser.truncated(maxLines: 100))
                                    .font(Typography.code)
                                    .foregroundStyle(outputParser.isSuccess ? colors.mutedForeground : colors.destructive)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                    .padding(Spacing.md)
                    .background(Color(hex: "0D0D0D").opacity(0.3))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.md) {
        BashToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Bash",
            input: "{\"command\": \"npm test\", \"description\": \"Run test suite\"}",
            output: "PASS  src/test.ts\n  Test Suite\n    ✓ should pass (5ms)\n    ✓ should handle errors (3ms)\n\nTest Suites: 1 passed, 1 total\nTests:       2 passed, 2 total",
            status: .completed
        ))

        BashToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Bash",
            input: "{\"command\": \"git status\"}",
            status: .running
        ))

        BashToolView(toolUse: ToolUse(
            toolUseId: "test-3",
            toolName: "Bash",
            input: "{\"command\": \"swift build\"}",
            output: "error: Missing dependency 'ArgumentParser'",
            status: .failed
        ))
    }
    .frame(width: 500)
    .padding()
}
