//
//  ToolHistoryEntryView.swift
//  unbound-macos
//
//  Renders a ToolHistoryEntry (completed tools/sub-agents from a previous turn).
//  Uses AgentCardView style for sub-agents with amber accent theme.
//

import SwiftUI

struct ToolHistoryEntryView: View {
    let entry: ToolHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let subAgent = entry.subAgent {
                ToolHistoryAgentCard(subAgent: subAgent)
            }

            if !entry.tools.isEmpty {
                ToolHistoryToolsCard(tools: entry.tools)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Tool History Agent Card

/// Displays a completed sub-agent with the new AgentCardView style.
private struct ToolHistoryAgentCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let subAgent: ActiveSubAgent
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var agentDisplayName: String {
        switch subAgent.subagentType.lowercased() {
        case "explore":
            return "Explore Agent"
        case "plan":
            return "Plan Agent"
        case "bash":
            return "Bash Agent"
        case "general-purpose":
            return "General Purpose Agent"
        default:
            return "\(subAgent.subagentType) Agent"
        }
    }

    private var agentIcon: String {
        switch subAgent.subagentType.lowercased() {
        case "explore":
            return "magnifyingglass"
        case "plan":
            return "list.bullet.clipboard"
        case "bash":
            return "terminal"
        case "general-purpose":
            return "cpu"
        default:
            return "cpu"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            header

            // Expanded content with nested tools
            if isExpanded && !subAgent.childTools.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(subAgent.childTools.enumerated()), id: \.element.id) { index, tool in
                        ToolHistoryToolRow(
                            tool: tool,
                            isLast: index == subAgent.childTools.count - 1
                        )
                    }
                }
                .padding(.leading, Spacing.xl + Spacing.md)
                .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.md)
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.md) {
                // Amber circular icon (muted for completed)
                Circle()
                    .fill(colors.accentAmberSubtle)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: agentIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.accentAmber.opacity(0.7))
                    )

                // Agent name and description
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(agentDisplayName)
                        .font(Typography.label)
                        .foregroundStyle(colors.sidebarText)

                    if !subAgent.description.isEmpty {
                        Text(subAgent.description)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Status indicator
                statusIndicator

                // Chevron
                if !subAgent.childTools.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch subAgent.status {
        case .running:
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(colors.accentAmber)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(colors.accentAmberSubtle)
            .clipShape(RoundedRectangle(cornerRadius: Radius.full))

        case .completed:
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(colors.success)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(colors.success.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Radius.full))

        case .failed:
            HStack(spacing: Spacing.xs) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(colors.destructive)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(colors.destructive.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Radius.full))
        }
    }
}

// MARK: - Tool History Tool Row

private struct ToolHistoryToolRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let tool: ActiveTool
    let isLast: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var toolIcon: String {
        switch tool.name {
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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Vertical connector line
            VStack(spacing: 0) {
                Rectangle()
                    .fill(colors.accentAmberHalf.opacity(0.5))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 1)
            .padding(.trailing, Spacing.md)

            // Tool content
            HStack(spacing: Spacing.sm) {
                // Horizontal connector to tool
                Rectangle()
                    .fill(colors.accentAmberHalf.opacity(0.5))
                    .frame(width: Spacing.sm, height: 1)

                // Tool icon
                Image(systemName: toolIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(colors.mutedForeground)
                    .frame(width: 14, height: 14)

                // Tool name and preview
                Text(tool.name)
                    .font(Typography.caption)
                    .foregroundStyle(colors.sidebarText)

                if let preview = tool.inputPreview {
                    Text(preview)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()

                // Tool status
                toolStatusIcon
            }
            .padding(.vertical, Spacing.xs)
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private var toolStatusIcon: some View {
        switch tool.status {
        case .running:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 8))
                .foregroundStyle(colors.success.opacity(0.7))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 8))
                .foregroundStyle(colors.destructive)
        }
    }
}

// MARK: - Tool History Tools Card

/// Displays standalone tools (not part of a sub-agent) in a card format.
private struct ToolHistoryToolsCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let tools: [ActiveTool]
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var toolCount: Int {
        tools.count
    }

    private var summaryText: String {
        if toolCount == 1 {
            return "1 tool completed"
        }
        return "\(toolCount) tools completed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: Duration.fast)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.md) {
                    // Tool icon
                    Circle()
                        .fill(colors.surface2)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 14))
                                .foregroundStyle(colors.mutedForeground)
                        )

                    // Summary
                    Text(summaryText)
                        .font(Typography.label)
                        .foregroundStyle(colors.sidebarText)

                    Spacer()

                    // Completed status
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(colors.success)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(colors.success.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.full))

                    // Chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded tools list
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                        ToolHistoryToolRow(
                            tool: tool,
                            isLast: index == tools.count - 1
                        )
                    }
                }
                .padding(.leading, Spacing.xl + Spacing.md)
                .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.md)
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.lg) {
        ToolHistoryEntryView(entry: ToolHistoryEntry(
            tools: [],
            subAgent: ActiveSubAgent(
                id: "agent-1",
                subagentType: "Explore",
                description: "Searching for authentication endpoints",
                childTools: [
                    ActiveTool(id: "t1", name: "Glob", inputPreview: "**/*.ts", status: .completed),
                    ActiveTool(id: "t2", name: "Grep", inputPreview: "authenticate", status: .completed),
                    ActiveTool(id: "t3", name: "Read", inputPreview: "src/auth/login.ts", status: .completed)
                ],
                status: .completed
            ),
            afterMessageIndex: 0
        ))

        ToolHistoryEntryView(entry: ToolHistoryEntry(
            tools: [
                ActiveTool(id: "t4", name: "Write", inputPreview: "src/new-file.ts", status: .completed),
                ActiveTool(id: "t5", name: "Bash", inputPreview: "npm test", status: .completed)
            ],
            subAgent: nil,
            afterMessageIndex: 1
        ))
    }
    .padding(Spacing.lg)
    .frame(width: 500)
    .background(Color(hex: "0D0D0D"))
}
