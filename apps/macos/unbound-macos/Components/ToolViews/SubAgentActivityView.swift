//
//  SubAgentActivityView.swift
//  unbound-macos
//
//  Sub-agent activity view matching Claude Code design.
//  Shows agent with amber icon, name, description, status badge,
//  and nested tools with amber vertical connector line.
//

import SwiftUI

struct SubAgentActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    let activity: SubAgentActivity
    @State private var isExpanded = true

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var agentDisplayName: String {
        switch activity.subagentType.lowercased() {
        case "explore":
            return "Explore Agent"
        case "plan":
            return "Plan Agent"
        case "bash":
            return "Bash Agent"
        case "general-purpose":
            return "General Purpose Agent"
        default:
            return "\(activity.subagentType) Agent"
        }
    }

    private var agentIcon: String {
        switch activity.subagentType.lowercased() {
        case "explore":
            return "binoculars.fill"
        case "plan":
            return "list.bullet.clipboard.fill"
        case "bash":
            return "terminal.fill"
        case "general-purpose":
            return "cpu.fill"
        default:
            return "cpu.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            header

            // Expanded content with nested tools
            if isExpanded && !activity.tools.isEmpty {
                toolsList
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                // Agent-colored circular icon
                Circle()
                    .fill(colors.agentAccentMutedColor(for: activity.subagentType))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: agentIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(colors.agentAccentColor(for: activity.subagentType))
                    )

                // Agent name (agent color)
                Text(agentDisplayName)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(colors.agentAccentColor(for: activity.subagentType))

                // Separator dot and description
                if !activity.description.isEmpty {
                    Text("·")
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)

                    Text(activity.description)
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()

                // Status badge
                statusBadge

                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(colors.mutedForeground)
            }
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Badge

    private var agentColor: Color {
        colors.agentAccentColor(for: activity.subagentType)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch activity.status {
        case .running:
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(agentColor)
                    .frame(width: 6, height: 6)
                Text("Running")
                    .font(Typography.caption)
                    .foregroundStyle(agentColor)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(agentColor)
            }

        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(colors.success)

        case .failed:
            HStack(spacing: Spacing.xs) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(colors.destructive)
                Text("Failed")
                    .font(Typography.caption)
                    .foregroundStyle(colors.destructive)
            }
        }
    }

    // MARK: - Tools List with Connector Lines

    private var toolsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(activity.tools.enumerated()), id: \.element.toolUseId) { index, tool in
                SubAgentToolRow(
                    tool: tool,
                    isLast: index == activity.tools.count - 1,
                    agentType: activity.subagentType
                )
            }
        }
        .padding(.leading, Spacing.md + 12) // Align with icon center
    }
}

// MARK: - Tool Row with Connector

private struct SubAgentToolRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let tool: ToolUse
    let isLast: Bool
    var agentType: String = "bash"

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var toolIcon: String {
        switch tool.toolName {
        case "Read": return "doc.text"
        case "Write": return "square.and.pencil"
        case "Edit": return "pencil"
        case "Glob": return "folder.badge.gearshape"
        case "Grep": return "magnifyingglass"
        case "Bash": return "terminal"
        case "WebFetch": return "globe"
        case "WebSearch": return "magnifyingglass.circle"
        default: return "wrench"
        }
    }

    private var toolPreview: String? {
        let parser = ToolInputParser(tool.input)
        return parser.filePath ?? parser.pattern ?? parser.command ?? parser.query ?? parser.url
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Connector lines
            connectorView

            // Tool content
            toolContent
        }
    }

    private var connectorColor: Color {
        colors.agentAccentColor(for: agentType).opacity(0.3)
    }

    private var connectorView: some View {
        HStack(spacing: 0) {
            // Vertical line
            GeometryReader { geometry in
                Rectangle()
                    .fill(connectorColor)
                    .frame(width: 1, height: isLast ? min(12, geometry.size.height) : geometry.size.height)
            }
            .frame(width: 1)

            // Horizontal connector
            Rectangle()
                .fill(connectorColor)
                .frame(width: Spacing.md, height: 1)
                .padding(.top, 10)
        }
        .frame(width: Spacing.lg)
    }

    private var toolContent: some View {
        HStack(spacing: Spacing.sm) {
            // Tool icon
            Image(systemName: toolIcon)
                .font(.system(size: 11))
                .foregroundStyle(colors.mutedForeground)
                .frame(width: 16, height: 16)

            // Tool name
            Text(tool.toolName)
                .font(Typography.body)
                .foregroundStyle(colors.foreground)

            // Preview/metadata
            if let preview = toolPreview {
                Text(preview)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            toolStatusIndicator
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var toolStatusIndicator: some View {
        switch tool.status {
        case .running:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(colors.success)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(colors.destructive)
        }
    }
}

// MARK: - Preview

#if DEBUG

#Preview {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        SubAgentActivityView(activity: SubAgentActivity(
            parentToolUseId: "task-1",
            subagentType: "Plan",
            description: "designing implementation plan",
            tools: [
                ToolUse(toolUseId: "t1", toolName: "Read", input: "{\"file_path\": \"ARCHITECTURE.md\"}", status: .completed),
                ToolUse(toolUseId: "t2", toolName: "Edit", input: "{\"file_path\": \"plan.md\"}", status: .running)
            ],
            status: .running
        ))

        SubAgentActivityView(activity: SubAgentActivity(
            parentToolUseId: "task-2",
            subagentType: "Explore",
            description: "searching codebase",
            tools: [
                ToolUse(toolUseId: "t3", toolName: "Glob", input: "{\"pattern\": \"**/*.rs\"}", status: .completed),
                ToolUse(toolUseId: "t4", toolName: "Read", input: "{\"file_path\": \"src/lib.rs\"}", status: .completed)
            ],
            status: .completed
        ))
    }
    .padding(Spacing.lg)
    .frame(width: 500)
    .background(Color(hex: "0D0D0D"))
}

#endif
