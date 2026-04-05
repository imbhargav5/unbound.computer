//
//  ToolHeader.swift
//  unbound-macos
//
//  Reusable header component for tool views
//

import SwiftUI

// MARK: - Tool Header

/// Reusable header component for all tool views
struct ToolHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolName: String
    let status: ToolStatus
    var subtitle: String?
    var icon: String?
    var isExpanded: Bool = false
    var hasContent: Bool = true
    var onToggle: (() -> Void)?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button {
            if hasContent {
                onToggle?()
            }
        } label: {
            HStack(spacing: Spacing.md) {
                // Status indicator
                statusIcon

                // Tool icon (if provided)
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                }

                // Tool name and subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(toolName)
                        .font(Typography.code)
                        .foregroundStyle(colors.foreground)

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

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
                if hasContent {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                }
            }
            .padding(Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
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
        switch status {
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        switch status {
        case .running: return colors.info
        case .completed: return colors.success
        case .failed: return colors.destructive
        }
    }
}

// MARK: - Tool Icons

/// Standard icons for each tool type
enum ToolIcon {
    static func icon(for toolName: String) -> String {
        switch toolName {
        case "Bash":
            return "terminal"
        case "Read":
            return "doc.text"
        case "Write":
            return "doc.badge.plus"
        case "Edit":
            return "pencil.line"
        case "Glob":
            return "folder.badge.gearshape"
        case "Grep":
            return "magnifyingglass"
        case "WebFetch":
            return "globe"
        case "WebSearch":
            return "magnifyingglass.circle"
        case "Task":
            return "gearshape.2"
        case "TaskCreate", "TaskUpdate", "TaskList", "TaskGet":
            return "checklist"
        case "AskUserQuestion":
            return "questionmark.circle"
        case "NotebookEdit":
            return "book"
        case "Skill":
            return "wand.and.stars"
        default:
            return "wrench"
        }
    }
}

// MARK: - Preview

#if DEBUG

#Preview {
    VStack(spacing: Spacing.md) {
        ToolHeader(
            toolName: "Bash",
            status: .running,
            subtitle: "npm test",
            icon: "terminal",
            isExpanded: false
        )

        ToolHeader(
            toolName: "Read",
            status: .completed,
            subtitle: "src/main.swift",
            icon: "doc.text",
            isExpanded: true
        )

        ToolHeader(
            toolName: "Edit",
            status: .failed,
            subtitle: "Package.swift",
            icon: "pencil.line",
            isExpanded: false
        )
    }
    .frame(width: 500)
    .padding()
}

#endif
