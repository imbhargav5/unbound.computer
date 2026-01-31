//
//  ToolHistoryEntryView.swift
//  unbound-macos
//
//  Renders a ToolHistoryEntry (completed tools/sub-agents from a previous turn).
//

import SwiftUI

struct ToolHistoryEntryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: ToolHistoryEntry

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // If this entry has a sub-agent, render it with its child tools
            if let subAgent = entry.subAgent {
                ToolHistorySubAgentView(subAgent: subAgent)
            }

            // Render standalone tools (not part of a sub-agent)
            if !entry.tools.isEmpty {
                ToolHistoryToolsView(tools: entry.tools)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Tool History Sub-Agent View

/// Renders a completed sub-agent from tool history
private struct ToolHistorySubAgentView: View {
    @Environment(\.colorScheme) private var colorScheme

    let subAgent: ActiveSubAgent
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var agentTypeColor: Color {
        switch subAgent.subagentType.lowercased() {
        case "explore":
            return colors.info
        case "plan":
            return colors.warning
        case "bash":
            return colors.success
        default:
            return colors.primary
        }
    }

    private var agentIcon: String {
        switch subAgent.subagentType.lowercased() {
        case "explore":
            return "magnifyingglass.circle"
        case "plan":
            return "map"
        case "bash":
            return "terminal"
        case "general-purpose":
            return "gearshape.2"
        default:
            return "sparkles"
        }
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
                    statusIcon

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: agentIcon)
                            .font(.system(size: IconSize.sm))

                        Text(subAgent.subagentType)
                            .font(Typography.label)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(agentTypeColor)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(agentTypeColor.opacity(0.1))
                    )

                    Text(subAgent.description)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if !subAgent.childTools.isEmpty {
                        Text("\(subAgent.childTools.count) tool\(subAgent.childTools.count == 1 ? "" : "s")")
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                }
                .padding(Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded && !subAgent.childTools.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ShadcnDivider()

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(subAgent.childTools, id: \.id) { tool in
                            ActiveToolRow(tool: tool)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
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

    @ViewBuilder
    private var statusIcon: some View {
        switch subAgent.status {
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
}

// MARK: - Tool History Tools View

/// Renders standalone tools from tool history (not part of a sub-agent)
private struct ToolHistoryToolsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tools: [ActiveTool]
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
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
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: 18, height: 18)

                    Text("\(tools.count) tool\(tools.count == 1 ? "" : "s") completed")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                }
                .padding(Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ShadcnDivider()

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(tools, id: \.id) { tool in
                            ActiveToolRow(tool: tool)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
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

#Preview {
    VStack(spacing: Spacing.lg) {
        // Entry with sub-agent
        ToolHistoryEntryView(entry: ToolHistoryEntry(
            tools: [],
            subAgent: ActiveSubAgent(
                id: "task-1",
                subagentType: "Explore",
                description: "Search for authentication endpoints",
                childTools: [
                    ActiveTool(id: "t1", name: "Glob", inputPreview: "**/*.ts", status: .completed),
                    ActiveTool(id: "t2", name: "Grep", inputPreview: "authenticate", status: .completed)
                ],
                status: .completed
            ),
            afterMessageIndex: 0
        ))

        // Entry with standalone tools
        ToolHistoryEntryView(entry: ToolHistoryEntry(
            tools: [
                ActiveTool(id: "t3", name: "Read", inputPreview: "README.md", status: .completed),
                ActiveTool(id: "t4", name: "Bash", inputPreview: "npm test", status: .completed)
            ],
            subAgent: nil,
            afterMessageIndex: 1
        ))
    }
    .frame(width: 500)
    .padding()
}
