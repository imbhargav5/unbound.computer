//
//  StandaloneToolCallsView.swift
//  unbound-macos
//
//  Unified standalone tool-calls surface for live and historical states.
//

import SwiftUI

private enum StandaloneToolCallsPayload {
    case active([ActiveTool])
    case historical([ToolUse])
}

struct StandaloneToolCallsView: View {
    private let payload: StandaloneToolCallsPayload

    init(activeTools: [ActiveTool]) {
        self.payload = .active(activeTools)
    }

    init(historyTools: [ToolUse]) {
        self.payload = .historical(historyTools)
    }

    var body: some View {
        switch payload {
        case .active(let tools):
            ActiveToolsView(tools: tools)

        case .historical(let tools):
            HistoricalStandaloneToolCallsCard(tools: tools)
        }
    }
}

private struct HistoricalStandaloneToolCallsCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let tools: [ToolUse]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var summaryText: String {
        let actionLines = ToolActivitySummary.actionLines(for: tools)
        if actionLines.isEmpty {
            return "Tool activity"
        }
        if actionLines.count == 1, let line = actionLines.first {
            return line.text
        }
        return "Ran \(actionLines.count) tool calls"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                    ToolUseView(toolUse: tool)
                        .padding(.horizontal, Spacing.md)

                    if index < tools.count - 1 {
                        ShadcnDivider()
                            .padding(.horizontal, Spacing.md)
                    }
                }
            }
            .padding(.bottom, Spacing.sm)
        }
        .background(colors.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(colors.panelDivider, lineWidth: BorderWidth.hairline)
        )
    }
}

private enum StandaloneToolCallsPreviewData {
    static let activeRunningSingle: [ActiveTool] = [
        ActiveTool(id: "live-tool-0", name: "Bash", inputPreview: "cargo test -p parser-contracts", status: .running),
    ]

    static let activeMixed: [ActiveTool] = [
        ActiveTool(id: "live-tool-1", name: "Glob", inputPreview: "**/*.swift", status: .completed),
        ActiveTool(id: "live-tool-2", name: "Grep", inputPreview: "raw_json", status: .running),
        ActiveTool(id: "live-tool-3", name: "Read", inputPreview: "SessionDetailMessageMapper.swift", status: .completed),
        ActiveTool(id: "live-tool-4", name: "Write", inputPreview: "SessionContract.md", status: .failed),
    ]

    static let activeCompleted: [ActiveTool] = [
        ActiveTool(id: "live-tool-5", name: "Read", inputPreview: "ClaudeMessageParser.swift", status: .completed),
        ActiveTool(id: "live-tool-6", name: "Write", inputPreview: "ParserSpec.md", status: .completed),
    ]

    static let historicalSingle: [ToolUse] = [
        ToolUse(
            toolUseId: "hist-tool-0",
            toolName: "Read",
            input: "{\"file_path\":\"SessionContentBlock.swift\"}",
            output: nil,
            status: .completed
        ),
    ]

    static let historicalMixed: [ToolUse] = [
        ToolUse(
            toolUseId: "hist-tool-1",
            toolName: "Bash",
            input: "{\"command\":\"xcodebuild -project apps/ios/unbound-ios.xcodeproj\"}",
            output: "BUILD SUCCEEDED",
            status: .completed
        ),
        ToolUse(
            toolUseId: "hist-tool-2",
            toolName: "Write",
            input: "{\"file_path\":\"Docs/parser-behavior.md\"}",
            output: nil,
            status: .failed
        ),
        ToolUse(
            toolUseId: "hist-tool-3",
            toolName: "Read",
            input: "{\"file_path\":\"ClaudeMessageParser.swift\"}",
            output: nil,
            status: .completed
        ),
    ]
}

#Preview("Standalone Tool Calls Variants") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        StandaloneToolCallsView(activeTools: StandaloneToolCallsPreviewData.activeRunningSingle)
        StandaloneToolCallsView(activeTools: StandaloneToolCallsPreviewData.activeMixed)
        StandaloneToolCallsView(activeTools: StandaloneToolCallsPreviewData.activeCompleted)
        StandaloneToolCallsView(historyTools: StandaloneToolCallsPreviewData.historicalSingle)
        StandaloneToolCallsView(historyTools: StandaloneToolCallsPreviewData.historicalMixed)
    }
    .frame(width: 540)
    .padding()
}
