//
//  ToolUseView.swift
//  unbound-macos
//
//  Display tool use with status and collapsible details
//

import SwiftUI

struct ToolUseView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var actionText: String {
        ToolActivitySummary.actionLine(for: toolUse)?.text ?? toolUse.toolName
    }

    private var hasDetails: Bool {
        (toolUse.input?.isEmpty == false) || (toolUse.output?.isEmpty == false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                if hasDetails {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(actionText)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text(statusName)
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)

                    if hasDetails {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(colors.mutedForeground)
                    }
                }
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Details (if expanded)
            if isExpanded && hasDetails {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ShadcnDivider()

                    // Input
                    if let input = toolUse.input, !input.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Input")
                                .font(Typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(colors.mutedForeground)

                            ScrollView {
                                Text(input)
                                    .font(Typography.code)
                                    .foregroundStyle(colors.foreground)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 100)
                            .padding(Spacing.sm)
                            .background(colors.muted)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }
                        .padding(.horizontal, Spacing.md)
                    }

                    // Output
                    if let output = toolUse.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Output")
                                .font(Typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(colors.mutedForeground)

                            ScrollView {
                                Text(output)
                                    .font(Typography.code)
                                    .foregroundStyle(colors.foreground)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150)
                            .padding(Spacing.sm)
                            .background(colors.muted)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.bottom, Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusName: String {
        switch toolUse.status {
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        switch toolUse.status {
        case .running: return colors.info
        case .completed: return colors.success
        case .failed: return colors.destructive
        }
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        ToolUseView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Read",
            input: "src/main.swift",
            output: "File contents here...",
            status: .completed
        ))

        ToolUseView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Bash",
            input: "npm test",
            output: nil,
            status: .running
        ))

        ToolUseView(toolUse: ToolUse(
            toolUseId: "test-3",
            toolName: "Bash",
            input: "swift build",
            output: "Error: Missing dependency",
            status: .failed
        ))
    }
    .frame(width: 500)
    .padding()
}
