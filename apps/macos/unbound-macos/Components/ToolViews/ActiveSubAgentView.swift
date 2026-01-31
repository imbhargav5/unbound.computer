//
//  ActiveSubAgentView.swift
//  unbound-macos
//
//  Collapsible container for an ActiveSubAgent (runtime state).
//  Shows the sub-agent header with child tools listed below.
//

import SwiftUI

struct ActiveSubAgentView: View {
    @Environment(\.colorScheme) private var colorScheme

    let subAgent: ActiveSubAgent
    @State private var isExpanded = true

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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subAgent.description)
                            .font(Typography.caption)
                            .foregroundStyle(colors.foreground)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !subAgent.childTools.isEmpty && !isExpanded {
                            Text("\(subAgent.childTools.count) tool\(subAgent.childTools.count == 1 ? "" : "s")")
                                .font(Typography.micro)
                                .foregroundStyle(colors.mutedForeground)
                        }
                    }

                    Spacer()

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
                        ForEach(subAgent.childTools, id: \.id) { tool in
                            ActiveToolRow(tool: tool)
                        }

                        if subAgent.childTools.isEmpty && subAgent.status == .running {
                            HStack(spacing: Spacing.sm) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Starting sub-agent...")
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.mutedForeground)
                            }
                            .padding(Spacing.md)
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
                    subAgent.status == .running ? agentTypeColor.opacity(0.5) : colors.border,
                    lineWidth: subAgent.status == .running ? BorderWidth.thick : BorderWidth.default
                )
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

    private var statusName: String {
        switch subAgent.status {
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        switch subAgent.status {
        case .running: return colors.info
        case .completed: return colors.success
        case .failed: return colors.destructive
        }
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        ActiveSubAgentView(subAgent: ActiveSubAgent(
            id: "task-1",
            subagentType: "Explore",
            description: "Search for authentication endpoints",
            childTools: [
                ActiveTool(id: "t1", name: "Glob", inputPreview: "**/*.ts", status: .completed),
                ActiveTool(id: "t2", name: "Grep", inputPreview: "authenticate", status: .completed),
                ActiveTool(id: "t3", name: "Read", inputPreview: "src/auth/login.ts", status: .running)
            ],
            status: .running
        ))

        ActiveSubAgentView(subAgent: ActiveSubAgent(
            id: "task-2",
            subagentType: "Plan",
            description: "Design implementation approach",
            childTools: [
                ActiveTool(id: "t4", name: "Read", inputPreview: "README.md", status: .completed),
                ActiveTool(id: "t5", name: "Glob", inputPreview: "src/**/*.swift", status: .completed)
            ],
            status: .completed
        ))

        ActiveSubAgentView(subAgent: ActiveSubAgent(
            id: "task-3",
            subagentType: "general-purpose",
            description: "Analyzing codebase structure",
            childTools: [],
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}
