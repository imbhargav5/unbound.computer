//
//  ToolHistoryEntryView.swift
//  unbound-macos
//
//  Renders a ToolHistoryEntry (completed tools/sub-agents from a previous turn).
//

import SwiftUI

struct ToolHistoryEntryView: View {
    let entry: ToolHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let subAgent = entry.subAgent {
                ToolHistorySubAgentView(subAgent: subAgent)
            }

            if !entry.tools.isEmpty {
                ToolHistoryToolsView(tools: entry.tools)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Tool History Sub-Agent View

private struct ToolHistorySubAgentView: View {
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

// MARK: - Tool History Tools View

private struct ToolHistoryToolsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tools: [ActiveTool]
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var summaryText: String {
        ToolActivitySummary.summary(for: tools)
    }

    private var actionLines: [ToolActionLine] {
        ToolActivitySummary.actionLines(for: tools)
    }

    private var hasDetails: Bool {
        !actionLines.isEmpty
    }

    private var detailPaddingLeading: CGFloat {
        Spacing.md + IconSize.sm + Spacing.sm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasDetails {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: IconSize.sm, height: IconSize.sm)

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
}
