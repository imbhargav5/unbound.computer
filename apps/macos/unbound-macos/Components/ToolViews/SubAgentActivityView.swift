//
//  SubAgentActivityView.swift
//  unbound-macos
//
//  Collapsible container for sub-agent (Task tool) activity
//  Groups child tools executed by sub-agents like Explore, Plan, general-purpose
//

import SwiftUI

// MARK: - Sub-Agent Activity View

/// Collapsible container displaying sub-agent activity with grouped child tools
struct SubAgentActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    let activity: SubAgentActivity
    @State private var isExpanded = true  // Default expanded while running

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Background color based on agent type
    private var agentTypeColor: Color {
        switch activity.subagentType.lowercased() {
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

    /// Icon for agent type
    private var agentIcon: String {
        switch activity.subagentType.lowercased() {
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
            SubAgentHeader(
                agentType: activity.subagentType,
                description: activity.description,
                toolCount: activity.tools.count,
                status: activity.status,
                icon: agentIcon,
                accentColor: agentTypeColor,
                isExpanded: isExpanded,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ShadcnDivider()

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        // Stream of child tools
                        ForEach(activity.tools) { tool in
                            CompactToolRow(toolUse: tool)
                        }

                        // Empty state if no tools yet
                        if activity.tools.isEmpty && activity.status == .running {
                            HStack(spacing: Spacing.sm) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Starting sub-agent...")
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.mutedForeground)
                            }
                            .padding(Spacing.md)
                        }

                        // Result (when complete)
                        if let result = activity.result, !result.isEmpty {
                            ResultSection(result: result)
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
                .stroke(
                    activity.status == .running ? agentTypeColor.opacity(0.5) : colors.border,
                    lineWidth: activity.status == .running ? BorderWidth.thick : BorderWidth.default
                )
        )
        // Auto-collapse when completed (optional enhancement)
        .onChange(of: activity.status) { _, newStatus in
            if newStatus == .completed {
                // Optional: auto-collapse after a delay
                // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                //     withAnimation { isExpanded = false }
                // }
            }
        }
    }
}

// MARK: - Sub-Agent Header

/// Header component for sub-agent activity with agent type badge, description, and status
struct SubAgentHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let agentType: String
    let description: String
    let toolCount: Int
    let status: ToolStatus
    let icon: String
    let accentColor: Color
    var isExpanded: Bool = false
    var onToggle: (() -> Void)?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button {
            onToggle?()
        } label: {
            HStack(spacing: Spacing.md) {
                // Status indicator
                statusIcon

                // Agent type badge with icon
                HStack(spacing: Spacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: IconSize.sm))

                    Text(agentType)
                        .font(Typography.label)
                        .fontWeight(.medium)
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(accentColor.opacity(0.1))
                )

                // Description
                VStack(alignment: .leading, spacing: 2) {
                    Text(description)
                        .font(Typography.caption)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if toolCount > 0 && !isExpanded {
                        Text("\(toolCount) tool\(toolCount == 1 ? "" : "s")")
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
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
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(colors.mutedForeground)
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

// MARK: - Result Section

/// Displays the final result from a sub-agent
private struct ResultSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let result: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Truncated result for display
    private var displayResult: String {
        if result.count > 500 {
            return String(result.prefix(500)) + "..."
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Result")
                .font(Typography.micro)
                .fontWeight(.medium)
                .foregroundStyle(colors.mutedForeground)

            ScrollView {
                Text(displayResult)
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
        .padding(.bottom, Spacing.sm)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.lg) {
        // Running sub-agent with tools
        SubAgentActivityView(activity: SubAgentActivity(
            parentToolUseId: "task-1",
            subagentType: "Explore",
            description: "Search for authentication endpoints",
            tools: [
                ToolUse(toolUseId: "t1", toolName: "Glob", input: "{\"pattern\": \"**/*.ts\"}", status: .completed),
                ToolUse(toolUseId: "t2", toolName: "Grep", input: "{\"pattern\": \"authenticate\"}", status: .completed),
                ToolUse(toolUseId: "t3", toolName: "Read", input: "{\"file_path\": \"src/auth/login.ts\"}", status: .running)
            ],
            status: .running
        ))

        // Completed sub-agent
        SubAgentActivityView(activity: SubAgentActivity(
            parentToolUseId: "task-2",
            subagentType: "Plan",
            description: "Design implementation approach",
            tools: [
                ToolUse(toolUseId: "t4", toolName: "Read", input: "{\"file_path\": \"README.md\"}", output: "# Project", status: .completed),
                ToolUse(toolUseId: "t5", toolName: "Glob", input: "{\"pattern\": \"src/**/*.swift\"}", output: "5 files", status: .completed)
            ],
            status: .completed,
            result: "Implementation plan created successfully. Found 5 relevant files to modify."
        ))

        // Empty running sub-agent
        SubAgentActivityView(activity: SubAgentActivity(
            parentToolUseId: "task-3",
            subagentType: "general-purpose",
            description: "Analyzing codebase structure",
            tools: [],
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}
