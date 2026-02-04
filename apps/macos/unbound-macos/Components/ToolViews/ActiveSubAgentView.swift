//
//  ActiveSubAgentView.swift
//  unbound-macos
//
//  Lightweight container for an ActiveSubAgent (runtime state).
//

import SwiftUI

struct ActiveSubAgentView: View {
    @Environment(\.colorScheme) private var colorScheme

    let subAgent: ActiveSubAgent
    @State private var isExpanded = true

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var summaryText: String {
        let toolUses = subAgent.childTools.map {
            ToolUse(toolName: $0.name, input: $0.inputPreview, status: $0.status)
        }
        return ToolActivitySummary.summary(for: subAgent.subagentType, tools: toolUses, status: subAgent.status)
    }

    private var actionLines: [ToolActionLine] {
        ToolActivitySummary.actionLines(for: subAgent.childTools)
    }

    private var hasDetails: Bool {
        !actionLines.isEmpty
    }

    private var detailPaddingLeading: CGFloat {
        Spacing.md + IconSize.sm + Spacing.sm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded && hasDetails {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ShadcnDivider()
                        .padding(.horizontal, Spacing.md)

                    ForEach(actionLines) { line in
                        Text(line.text)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                            .padding(.leading, detailPaddingLeading)
                            .padding(.trailing, Spacing.md)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    private var header: some View {
        Button {
            if hasDetails {
                withAnimation(.easeInOut(duration: Duration.fast)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                statusIcon

                Text(summaryText)
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)

                Spacer()

                if hasDetails {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch subAgent.status {
        case .running:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: IconSize.sm, height: IconSize.sm)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: IconSize.xs))
                .foregroundStyle(colors.mutedForeground)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: IconSize.xs))
                .foregroundStyle(colors.destructive)
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
    }
    .frame(width: 520)
    .padding()
}
