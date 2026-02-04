//
//  SubAgentActivityView.swift
//  unbound-macos
//
//  Lightweight container for sub-agent (Task tool) activity.
//

import SwiftUI

struct SubAgentActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    let activity: SubAgentActivity
    @State private var isExpanded = true

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var summaryText: String {
        ToolActivitySummary.summary(for: activity.subagentType, tools: activity.tools, status: activity.status)
    }

    private var actionLines: [ToolActionLine] {
        ToolActivitySummary.actionLines(for: activity.tools)
    }

    private var hasDetails: Bool {
        !actionLines.isEmpty || (activity.result?.isEmpty == false)
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

                    if let result = activity.result, !result.isEmpty {
                        Text(result)
                            .font(Typography.caption)
                            .foregroundStyle(colors.foreground)
                            .padding(.leading, detailPaddingLeading)
                            .padding(.trailing, Spacing.md)
                            .padding(.top, Spacing.xs)
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
        switch activity.status {
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
    }
    .frame(width: 520)
    .padding()
}
