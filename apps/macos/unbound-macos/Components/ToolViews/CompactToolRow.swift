//
//  CompactToolRow.swift
//  unbound-macos
//
//  Compact single-line tool display for nested tools inside sub-agent containers
//

import SwiftUI

// MARK: - Compact Tool Row

/// Single-line compact view for tools inside a sub-agent container
struct CompactToolRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    /// Get a brief subtitle based on tool type
    private var subtitle: String {
        switch toolUse.toolName {
        case "Bash":
            return parser.command ?? parser.commandDescription ?? ""
        case "Read", "Write":
            return parser.filePath?.components(separatedBy: "/").last ?? parser.filePath ?? ""
        case "Edit":
            return parser.filePath?.components(separatedBy: "/").last ?? ""
        case "Glob":
            return parser.pattern ?? ""
        case "Grep":
            return parser.pattern ?? ""
        case "WebFetch":
            // Extract domain from URL
            if let url = parser.url, let urlObj = URL(string: url) {
                return urlObj.host ?? url
            }
            return parser.url ?? ""
        case "WebSearch":
            return parser.query ?? ""
        default:
            return parser.taskDescription ?? ""
        }
    }

    /// Icon for the tool
    private var toolIcon: String {
        ToolIcon.icon(for: toolUse.toolName)
    }

    /// Icon color based on tool type
    private var iconColor: Color {
        switch toolUse.toolName {
        case "Bash":
            return colors.success
        case "Read":
            return colors.info
        case "Write":
            return Color.orange
        case "Edit":
            return Color.purple
        case "Glob":
            return Color.cyan
        case "Grep":
            return Color.yellow
        case "WebFetch", "WebSearch":
            return Color.blue
        default:
            return colors.mutedForeground
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                if hasExpandableContent {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    // Tool icon
                    Image(systemName: toolIcon)
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(iconColor)
                        .frame(width: 20)

                    // Tool name
                    Text(toolUse.toolName)
                        .font(Typography.code)
                        .foregroundStyle(colors.foreground)

                    // Subtitle
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    // Status indicator
                    statusIndicator

                    // Expand indicator if has content
                    if hasExpandableContent {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(colors.mutedForeground)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded, let output = toolUse.output, !output.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ScrollView {
                        Text(truncatedOutput)
                            .font(Typography.code)
                            .foregroundStyle(colors.foreground)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)
                .padding(.leading, 20 + Spacing.sm)  // Align with tool name
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(isExpanded ? colors.muted.opacity(0.5) : Color.clear)
        )
    }

    /// Whether this tool has expandable content
    private var hasExpandableContent: Bool {
        toolUse.output != nil && !toolUse.output!.isEmpty
    }

    /// Truncated output for display
    private var truncatedOutput: String {
        guard let output = toolUse.output else { return "" }
        let lines = output.components(separatedBy: .newlines)
        if lines.count > 10 {
            return lines.prefix(10).joined(separator: "\n") + "\n... (\(lines.count - 10) more lines)"
        }
        return output
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch toolUse.status {
        case .running:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(colors.success)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(colors.destructive)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        CompactToolRow(toolUse: ToolUse(
            toolUseId: "t1",
            toolName: "Glob",
            input: "{\"pattern\": \"**/*.swift\"}",
            output: "src/main.swift\nsrc/utils.swift\ntests/test.swift",
            status: .completed
        ))

        CompactToolRow(toolUse: ToolUse(
            toolUseId: "t2",
            toolName: "Grep",
            input: "{\"pattern\": \"authenticate\"}",
            output: "src/auth.swift:42: func authenticate()",
            status: .completed
        ))

        CompactToolRow(toolUse: ToolUse(
            toolUseId: "t3",
            toolName: "Read",
            input: "{\"file_path\": \"/src/auth/login.ts\"}",
            status: .running
        ))

        CompactToolRow(toolUse: ToolUse(
            toolUseId: "t4",
            toolName: "Bash",
            input: "{\"command\": \"npm test\", \"description\": \"Run test suite\"}",
            output: "PASS all tests",
            status: .completed
        ))

        CompactToolRow(toolUse: ToolUse(
            toolUseId: "t5",
            toolName: "WebSearch",
            input: "{\"query\": \"Swift concurrency best practices\"}",
            status: .failed
        ))
    }
    .frame(width: 450)
    .padding()
    .background(Color.gray.opacity(0.1))
}
