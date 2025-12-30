//
//  ToolUseView.swift
//  rocketry-macos
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                if toolUse.input != nil || toolUse.output != nil {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: Spacing.md) {
                    // Status indicator
                    statusIcon

                    // Tool name
                    Text(toolUse.toolName)
                        .font(Typography.code)
                        .foregroundStyle(colors.foreground)

                    Spacer()

                    // Status badge
                    Text(statusName)
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(statusColor.opacity(0.1))
                        )

                    // Expand indicator
                    if toolUse.input != nil || toolUse.output != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)
                    }
                }
                .padding(Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Details (if expanded)
            if isExpanded {
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
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toolUse.status {
        case .running:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 18, height: 18)

        case .completed:
            ZStack {
                Circle()
                    .fill(colors.success)
                    .frame(width: 18, height: 18)

                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }

        case .failed:
            ZStack {
                Circle()
                    .fill(colors.destructive)
                    .frame(width: 18, height: 18)

                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
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
