//
//  StandaloneToolCallsView.swift
//  unbound-macos
//
//  Unified standalone tool-calls surface for live and historical states.
//

import Foundation
import SwiftUI

private enum StandaloneToolCallsPayload {
    case active([ActiveTool])
    case historical([ToolUse])
}

struct StandaloneToolCallsView: View {
    private let payload: StandaloneToolCallsPayload

    init(activeTools: [ActiveTool], initiallyExpanded: Bool = true) {
        self.payload = .active(activeTools)
        _ = initiallyExpanded
    }

    init(historyTools: [ToolUse], initiallyExpanded: Bool = true) {
        self.payload = .historical(historyTools)
        _ = initiallyExpanded
    }

    private var toolUses: [ToolUse] {
        switch payload {
        case .active(let tools):
            return tools.map { tool in
                let parserKey: String = switch tool.name {
                case "Read", "Write", "Edit": "file_path"
                case "Bash": "command"
                case "Glob", "Grep": "pattern"
                case "WebSearch": "query"
                case "WebFetch": "url"
                default: "description"
                }
                let payload = [parserKey: tool.inputPreview ?? ""]
                let input = (try? JSONSerialization.data(withJSONObject: payload))
                    .flatMap { String(data: $0, encoding: .utf8) }

                return ToolUse(
                    toolUseId: tool.id,
                    toolName: tool.name,
                    input: input,
                    output: tool.output,
                    status: tool.status
                )
            }
        case .historical(let tools):
            return tools
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(toolUses) { tool in
                ToolViewRouter(toolUse: tool)
            }
        }
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
        StandaloneToolCallsView(activeTools: StandaloneToolCallsPreviewData.activeMixed, initiallyExpanded: false)
        StandaloneToolCallsView(historyTools: StandaloneToolCallsPreviewData.historicalSingle)
        StandaloneToolCallsView(historyTools: StandaloneToolCallsPreviewData.historicalMixed)
        StandaloneToolCallsView(historyTools: StandaloneToolCallsPreviewData.historicalMixed, initiallyExpanded: false)
    }
    .frame(width: 540)
    .padding()
}
