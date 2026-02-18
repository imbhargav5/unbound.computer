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
    @State private var isExpanded: Bool

    init(toolUse: ToolUse, initiallyExpanded: Bool = false) {
        self.toolUse = toolUse
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    private var actionText: String {
        toolUse.toolName
    }

    private var subtitle: String? {
        parser.filePath
            ?? parser.pattern
            ?? parser.commandDescription
            ?? parser.command
            ?? parser.query
            ?? parser.url
    }

    private var hasDetails: Bool {
        (toolUse.input?.isEmpty == false) || (toolUse.output?.isEmpty == false)
    }

    private var toolIcon: String {
        ToolIcon.icon(for: toolUse.toolName)
    }

    private var cardBorderColor: Color {
        switch toolUse.status {
        case .running:
            return Color(hex: "F59E0B30")
        case .completed:
            return Color(hex: "2A2A2A")
        case .failed:
            return Color(hex: "F8714930")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasDetails {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: toolIcon)
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: 16, height: 16)

                        Text(actionText)
                            .font(Typography.code)
                            .foregroundStyle(colors.foreground)
                            .lineLimit(1)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    Text(statusName)
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)

                    if hasDetails {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(colors.mutedForeground)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isExpanded && hasDetails {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let input = toolUse.input, !input.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Input")
                                .font(Typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(colors.mutedForeground)

                            ScrollView {
                                Text(input)
                                    .font(Typography.code)
                                    .foregroundStyle(colors.textMuted)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 120)
                        }
                    }

                    if let output = toolUse.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Output")
                                .font(Typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(colors.mutedForeground)

                            ScrollView {
                                Text(output)
                                    .font(Typography.code)
                                    .foregroundStyle(colors.textMuted)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(hex: "0D0D0D"))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "2A2A2A"))
                        .frame(height: 1)
                }
            }
        }
        .background(Color(hex: "111111"))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(cardBorderColor, lineWidth: BorderWidth.default)
        )
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
        ), initiallyExpanded: true)

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
        ), initiallyExpanded: true)
    }
    .frame(width: 500)
    .padding()
}
