//
//  AgentCardView.swift
//  unbound-macos
//
//  Agent card component matching the Claude Code design.
//  Shows agent type with amber icon, description, status, and nested tools
//  with vertical connector lines.
//

import SwiftUI

struct AgentCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let subAgent: ActiveSubAgent
    @State private var isExpanded = true

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
                        AgentToolRow(
                            tool: tool,
                            isLast: index == subAgent.childTools.count - 1
                        )
                    }
                }
                .padding(.leading, Spacing.xl + Spacing.md) // Align with header text
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
                // Amber circular icon
                Circle()
                    .fill(colors.accentAmberMuted)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: agentIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.accentAmber)
                    )

                // Agent name and description
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(agentDisplayName)
                        .font(Typography.label)
                        .foregroundStyle(colors.foreground)

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
                Text("Running")
                    .font(Typography.micro)
                    .foregroundStyle(colors.accentAmber)
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
                Text("Done")
                    .font(Typography.micro)
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
                Text("Failed")
                    .font(Typography.micro)
                    .foregroundStyle(colors.destructive)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(colors.destructive.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Radius.full))
        }
    }
}

// MARK: - Agent Tool Row

struct AgentToolRow: View {
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
                    .fill(colors.accentAmberHalf)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 1)
            .padding(.trailing, Spacing.md)

            // Tool content
            HStack(spacing: Spacing.sm) {
                // Horizontal connector to tool
                Rectangle()
                    .fill(colors.accentAmberHalf)
                    .frame(width: Spacing.sm, height: 1)

                // Tool icon
                Image(systemName: toolIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(colors.mutedForeground)
                    .frame(width: 14, height: 14)

                // Tool name and preview
                Text(tool.name)
                    .font(Typography.caption)
                    .foregroundStyle(colors.foreground)

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
                .foregroundStyle(colors.success)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 8))
                .foregroundStyle(colors.destructive)
        }
    }
}

// MARK: - Historical Agent Card View

struct HistoricalAgentCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let activity: SubAgentActivity
    @State private var isExpanded = false

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
            if isExpanded && !activity.tools.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activity.tools.enumerated()), id: \.element.id) { index, tool in
                        HistoricalToolRow(
                            tool: tool,
                            isLast: index == activity.tools.count - 1
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

                    if !activity.description.isEmpty {
                        Text(activity.description)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)
                    }
                }

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
                if !activity.tools.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Historical Tool Row

struct HistoricalToolRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let tool: ToolUse
    let isLast: Bool

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
                Text(tool.toolName)
                    .font(Typography.caption)
                    .foregroundStyle(colors.sidebarText)

                if let preview = extractPreview(from: tool.input) {
                    Text(preview)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()

                // Tool status
                Image(systemName: "checkmark")
                    .font(.system(size: 8))
                    .foregroundStyle(colors.success.opacity(0.7))
            }
            .padding(.vertical, Spacing.xs)
        }
        .frame(minHeight: 24)
    }

    private func extractPreview(from input: String?) -> String? {
        guard let input else { return nil }

        // Try to parse as JSON and extract relevant fields
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Extract based on tool type
        if let filePath = json["file_path"] as? String {
            return filePath
        }
        if let pattern = json["pattern"] as? String {
            return pattern
        }
        if let command = json["command"] as? String {
            return String(command.prefix(40))
        }

        return nil
    }
}

// MARK: - Previews

#Preview("Active Agent Card") {
    VStack(spacing: Spacing.lg) {
        AgentCardView(subAgent: ActiveSubAgent(
            id: "agent-1",
            subagentType: "Explore",
            description: "Searching for authentication endpoints",
            childTools: [
                ActiveTool(id: "t1", name: "Glob", inputPreview: "**/*.ts", status: .completed),
                ActiveTool(id: "t2", name: "Grep", inputPreview: "authenticate", status: .completed),
                ActiveTool(id: "t3", name: "Read", inputPreview: "src/auth/login.ts", status: .running)
            ],
            status: .running
        ))

        AgentCardView(subAgent: ActiveSubAgent(
            id: "agent-2",
            subagentType: "Plan",
            description: "Creating implementation strategy",
            childTools: [
                ActiveTool(id: "t4", name: "Read", inputPreview: "README.md", status: .completed),
                ActiveTool(id: "t5", name: "Read", inputPreview: "package.json", status: .completed)
            ],
            status: .completed
        ))

        AgentCardView(subAgent: ActiveSubAgent(
            id: "agent-3",
            subagentType: "Bash",
            description: "Running npm install",
            childTools: [
                ActiveTool(id: "t6", name: "Bash", inputPreview: "npm install", status: .failed)
            ],
            status: .failed
        ))
    }
    .padding(Spacing.lg)
    .frame(width: 500)
    .background(Color(hex: "0D0D0D"))
}
