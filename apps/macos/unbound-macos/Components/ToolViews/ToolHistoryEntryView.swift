//
//  ToolHistoryEntryView.swift
//  unbound-macos
//
//  Renders historical tool activity using the shared sub-agent and standalone
//  tool-call components.
//

import Foundation
import SwiftUI

struct ToolHistoryEntryView: View {
    let entry: ToolHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let subAgent = entry.subAgent {
                ParallelAgentsView(activities: [subAgent.asHistoricalActivity], defaultExpanded: false)
            }

            if !entry.tools.isEmpty {
                StandaloneToolCallsView(
                    historyTools: entry.tools.map { $0.asHistoricalToolUse() },
                    initiallyExpanded: false
                )
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }
}

private extension ActiveSubAgent {
    var asHistoricalActivity: SubAgentActivity {
        SubAgentActivity(
            parentToolUseId: id,
            subagentType: subagentType,
            description: description,
            tools: childTools.map { $0.asHistoricalToolUse(parentToolUseId: id) },
            status: status
        )
    }
}

private extension ActiveTool {
    func asHistoricalToolUse(parentToolUseId: String? = nil) -> ToolUse {
        ToolUse(
            toolUseId: id,
            parentToolUseId: parentToolUseId,
            toolName: name,
            input: normalizedToolInput,
            output: output,
            status: status
        )
    }

    var normalizedToolInput: String? {
        guard let inputPreview, !inputPreview.isEmpty else { return nil }

        let key: String
        switch name {
        case "Read", "Write", "Edit":
            key = "file_path"
        case "Bash":
            key = "command"
        case "Glob", "Grep":
            key = "pattern"
        case "WebSearch":
            key = "query"
        case "WebFetch":
            key = "url"
        default:
            key = "description"
        }

        let payload: [String: String] = [key: inputPreview]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return inputPreview
        }

        return json
    }
}

#if DEBUG

#Preview {
    VStack(spacing: Spacing.lg) {
        ToolHistoryEntryView(entry: ToolHistoryEntry(
            tools: [],
            subAgent: ActiveSubAgent(
                id: "agent-1",
                subagentType: "Explore",
                description: "Searching for parser regressions",
                childTools: [
                    ActiveTool(id: "t1", name: "Glob", inputPreview: "**/*.swift", status: .completed),
                    ActiveTool(id: "t2", name: "Read", inputPreview: "ClaudeMessageParser.swift", status: .completed),
                    ActiveTool(id: "t3", name: "Bash", inputPreview: "xcodebuild -scheme unbound-macos", status: .failed),
                ],
                status: .failed
            ),
            afterMessageIndex: 0
        ))

        ToolHistoryEntryView(entry: ToolHistoryEntry(
            tools: [
                ActiveTool(id: "t4", name: "Read", inputPreview: "SessionDetailView.swift", status: .completed),
                ActiveTool(id: "t5", name: "Write", inputPreview: "ParserContract.md", status: .completed),
            ],
            subAgent: nil,
            afterMessageIndex: 1
        ))
    }
    .padding(Spacing.lg)
    .frame(width: 540)
}

#endif
