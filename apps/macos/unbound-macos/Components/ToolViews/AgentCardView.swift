//
//  AgentCardView.swift
//  unbound-macos
//
//  Inline agent card component matching the Claude Code design.
//  Shows agent type with amber icon, description, status, and nested tools
//  in a flat, inline style without card backgrounds.
//

import SwiftUI

// MARK: - Agent Card View

struct AgentCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let subAgent: ActiveSubAgent
    @State private var isExpanded: Bool

    init(subAgent: ActiveSubAgent, initiallyExpanded: Bool = true) {
        self.subAgent = subAgent
        _isExpanded = State(initialValue: initiallyExpanded)
    }

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
            if isExpanded && !subAgent.childTools.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(subAgent.childTools.enumerated()), id: \.element.id) { index, tool in
                        AgentToolRow(
                            tool: tool,
                            isLast: index == subAgent.childTools.count - 1,
                            agentType: subAgent.subagentType
                        )
                    }
                }
                .padding(.leading, Spacing.lg)
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                // Agent-colored circular icon
                Circle()
                    .fill(colors.agentAccentMutedColor(for: subAgent.subagentType))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: agentIcon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(colors.agentAccentColor(for: subAgent.subagentType))
                    )

                // Agent name (bold, agent color)
                Text(agentDisplayName)
                    .font(Typography.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.agentAccentColor(for: subAgent.subagentType))

                // Separator dot
                if !subAgent.description.isEmpty {
                    Text("·")
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)

                    // Description
                    Text(subAgent.description)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()

                // Status indicator with dropdown chevron
                statusIndicator

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

    private var agentColor: Color {
        colors.agentAccentColor(for: subAgent.subagentType)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch subAgent.status {
        case .running:
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(agentColor)
                    .frame(width: 6, height: 6)
                Text("Running")
                    .font(Typography.micro)
                    .foregroundStyle(agentColor)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(agentColor)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(agentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Radius.full))

        case .completed:
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(colors.success)
            }

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
}

// MARK: - Agent Tool Row

struct AgentToolRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let tool: ActiveTool
    let isLast: Bool
    let agentType: String

    @State private var isExpanded = true

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

    /// Format the tool display based on type and input
    private var toolDisplayText: String {
        tool.name
    }

    /// Extract metadata like line count or file path
    private var toolMetadata: String? {
        tool.inputPreview
    }

    /// Whether the vertical line should be truncated (last item that's not running)
    private var shouldTruncateLine: Bool {
        isLast && tool.status != .running
    }

    /// Agent-specific connector color at 30% opacity
    private var connectorColor: Color {
        colors.agentAccentColor(for: agentType).opacity(0.3)
    }

    /// Connector view with vertical and horizontal lines
    @ViewBuilder
    private var connectorView: some View {
        HStack(spacing: 0) {
            // Vertical line - use GeometryReader to properly constrain height
            GeometryReader { geometry in
                Rectangle()
                    .fill(connectorColor)
                    .frame(width: 1, height: shouldTruncateLine ? min(12, geometry.size.height) : geometry.size.height)
            }
            .frame(width: 1)

            // Horizontal connector
            Rectangle()
                .fill(connectorColor)
                .frame(width: Spacing.md, height: 1)
                .padding(.top, 10)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tool header row
            HStack(alignment: .top, spacing: 0) {
                // Left connector area
                connectorView
                    .frame(width: Spacing.lg)

                // Tool content
                toolContent
            }

            // Bash output (inline, expanded)
            if tool.name == "Bash" && isExpanded {
                bashOutputView
                    .padding(.leading, Spacing.lg + Spacing.md)
            }
        }
    }

    private var toolContent: some View {
        HStack(spacing: Spacing.sm) {
            // Tool icon
            Image(systemName: toolIcon)
                .font(.system(size: 11))
                .foregroundStyle(colors.mutedForeground)
                .frame(width: 16, height: 16)

            // Tool name
            Text(toolDisplayText)
                .font(Typography.bodySmall)
                .foregroundStyle(colors.foreground)

            // Metadata (file path, line count, etc.)
            if let metadata = toolMetadata {
                Text(metadata)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            toolStatusIndicator
        }
        .padding(.vertical, Spacing.xxs)
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

    @ViewBuilder
    private var bashOutputView: some View {
        if let output = tool.output, !output.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Command prompt style
                if let command = tool.inputPreview {
                    HStack(spacing: Spacing.xs) {
                        Text(">_")
                            .font(Typography.code)
                            .foregroundStyle(colors.mutedForeground)
                        Text(command)
                            .font(Typography.code)
                            .foregroundStyle(colors.foreground)
                    }
                }

                // Output with syntax highlighting for test results
                BashOutputText(output: output, colors: colors)
            }
            .padding(Spacing.sm)
            .background(colors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(colors.border, lineWidth: BorderWidth.hairline)
            )
        }
    }
}

// MARK: - Bash Output Text (with test result coloring)

struct BashOutputText: View {
    let output: String
    let colors: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(output.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                coloredLine(line)
            }
        }
        .font(Typography.code)
    }

    @ViewBuilder
    private func coloredLine(_ line: String) -> some View {
        if line.contains("✓") || line.lowercased().contains("pass") {
            Text(line)
                .foregroundStyle(colors.success)
        } else if line.contains("✗") || line.lowercased().contains("fail") || line.lowercased().contains("error") {
            Text(line)
                .foregroundStyle(colors.destructive)
        } else if line.contains("running") || line.contains("...") {
            Text(line)
                .foregroundStyle(colors.accentAmber)
        } else {
            Text(line)
                .foregroundStyle(colors.mutedForeground)
        }
    }
}

// MARK: - Active Tool Row (for activity display)

struct ActivityToolRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let text: String
    let isActive: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? colors.accentAmber : colors.mutedForeground)

            Text(text)
                .font(Typography.body)
                .foregroundStyle(isActive ? colors.foreground : colors.mutedForeground)

            if isActive {
                Spacer()
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Historical Agent Card View

struct HistoricalAgentCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let activity: SubAgentActivity
    @State private var isExpanded: Bool

    init(activity: SubAgentActivity, initiallyExpanded: Bool = false) {
        self.activity = activity
        _isExpanded = State(initialValue: initiallyExpanded)
    }

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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activity.tools.enumerated()), id: \.element.id) { index, tool in
                        HistoricalToolRow(
                            tool: tool,
                            isLast: index == activity.tools.count - 1,
                            agentType: activity.subagentType
                        )
                    }
                }
                .padding(.leading, Spacing.lg)
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                // Agent-colored circular icon (slightly muted for completed)
                Circle()
                    .fill(colors.agentAccentMutedColor(for: activity.subagentType).opacity(0.75))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: agentIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(colors.agentAccentColor(for: activity.subagentType).opacity(0.7))
                    )

                // Agent name (agent color, slightly muted)
                Text(agentDisplayName)
                    .font(Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.agentAccentColor(for: activity.subagentType).opacity(0.8))

                // Separator dot
                if !activity.description.isEmpty {
                    Text("·")
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)

                    // Description
                    Text(activity.description)
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()

                // Completed checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(colors.success)

                // Expand/collapse chevron
                if !activity.tools.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colors.mutedForeground)
                }
            }
            .padding(.vertical, Spacing.sm)
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

    /// Agent-specific connector color at 20% opacity (muted for historical)
    private var connectorColor: Color {
        colors.agentAccentColor(for: agentType).opacity(0.2)
    }

    /// Connector view with vertical and horizontal lines
    @ViewBuilder
    private var connectorView: some View {
        HStack(spacing: 0) {
            // Vertical line - use GeometryReader to properly constrain height
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
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left connector area
            connectorView
                .frame(width: Spacing.lg)

            // Tool content
            HStack(spacing: Spacing.sm) {
                // Tool icon
                Image(systemName: toolIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(colors.mutedForeground)
                    .frame(width: 16, height: 16)

                // Tool name
                Text(tool.toolName)
                    .font(Typography.body)
                    .foregroundStyle(colors.sidebarText)

                // Preview/metadata
                if let preview = extractPreview(from: tool.input) {
                    Text(preview)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()

                // Completed checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(colors.success.opacity(0.7))
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func extractPreview(from input: String?) -> String? {
        guard let input else { return nil }

        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

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

#if DEBUG

#Preview("Active Agent Card") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        AgentCardView(subAgent: ActiveSubAgent(
            id: "agent-1",
            subagentType: "Explore",
            description: "exploring armin crate architecture",
            childTools: [
                ActiveTool(id: "t1", name: "Glob", inputPreview: "**/*.rs", status: .completed),
                ActiveTool(id: "t2", name: "Read", inputPreview: "src/lib.rs", status: .completed)
            ],
            status: .completed
        ))

        AgentCardView(subAgent: ActiveSubAgent(
            id: "agent-2",
            subagentType: "Plan",
            description: "designing implementation plan",
            childTools: [
                ActiveTool(id: "t3", name: "Read", inputPreview: "ARCHITECTURE.md", status: .completed, output: nil),
                ActiveTool(id: "t4", name: "Edit", inputPreview: "Writing implementation plan...", status: .running)
            ],
            status: .running
        ))

        AgentCardView(subAgent: ActiveSubAgent(
            id: "agent-3",
            subagentType: "Bash",
            description: "running npm test",
            childTools: [
                ActiveTool(
                    id: "t5",
                    name: "Bash",
                    inputPreview: "npm test",
                    status: .running,
                    output: "> unbound@0.1.0 test\n> vitest run\n\n✓ src/utils/parser.test.ts (12 tests) 45ms\n✓ src/utils/validator.test.ts (8 tests) 23ms\n✓ src/core/session.test.ts (15 tests) 89ms\n⠋ src/core/storage.test.ts running..."
                )
            ],
            status: .running
        ))

        AgentCardView(
            subAgent: ActiveSubAgent(
                id: "agent-4",
                subagentType: "general-purpose",
                description: "long summary and fallback icon handling for preview validation",
                childTools: [
                    ActiveTool(id: "t6", name: "CustomTool", inputPreview: "fallback preview content", status: .completed),
                ],
                status: .completed
            ),
            initiallyExpanded: false
        )
    }
    .padding(Spacing.lg)
    .frame(width: 500)
    .background(Color(hex: "0D0D0D"))
}

#Preview("Historical Agent Card") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        HistoricalAgentCardView(activity: SubAgentActivity(
            parentToolUseId: "hist-1",
            subagentType: "Explore",
            description: "searched codebase for auth",
            tools: [
                ToolUse(toolUseId: "h1", toolName: "Glob", input: "{\"pattern\": \"**/*.ts\"}", status: .completed),
                ToolUse(toolUseId: "h2", toolName: "Grep", input: "{\"pattern\": \"authenticate\"}", status: .completed)
            ],
            status: .completed
        ))

        HistoricalAgentCardView(
            activity: SubAgentActivity(
                parentToolUseId: "hist-2",
                subagentType: "general-purpose",
                description: "collapsed historical card preview state",
                tools: [],
                status: .completed
            ),
            initiallyExpanded: true
        )
    }
    .padding(Spacing.lg)
    .frame(width: 500)
    .background(Color(hex: "0D0D0D"))
}

#endif
