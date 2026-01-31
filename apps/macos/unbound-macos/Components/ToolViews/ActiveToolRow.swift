//
//  ActiveToolRow.swift
//  unbound-macos
//
//  Compact single-line view for an ActiveTool (runtime state).
//  Used inside ActiveSubAgentView and ActiveToolsView.
//

import SwiftUI

struct ActiveToolRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let tool: ActiveTool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var toolIcon: String {
        ToolIcon.icon(for: tool.name)
    }

    private var iconColor: Color {
        switch tool.name {
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
        HStack(spacing: Spacing.sm) {
            Image(systemName: toolIcon)
                .font(.system(size: IconSize.sm))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(tool.name)
                .font(Typography.code)
                .foregroundStyle(colors.foreground)

            if let preview = tool.inputPreview, !preview.isEmpty {
                Text(preview)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            statusIndicator
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch tool.status {
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

#Preview {
    VStack(spacing: 0) {
        ActiveToolRow(tool: ActiveTool(
            id: "t1",
            name: "Glob",
            inputPreview: "**/*.swift",
            status: .completed
        ))

        ActiveToolRow(tool: ActiveTool(
            id: "t2",
            name: "Grep",
            inputPreview: "authenticate",
            status: .running
        ))

        ActiveToolRow(tool: ActiveTool(
            id: "t3",
            name: "Read",
            inputPreview: "/src/auth/login.ts",
            status: .failed
        ))
    }
    .frame(width: 450)
    .padding()
    .background(Color.gray.opacity(0.1))
}
