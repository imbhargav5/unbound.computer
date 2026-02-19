import Foundation

struct ChatToolSurfaceDeduper {
    struct DisplayState {
        let visibleToolHistory: [ToolHistoryEntry]
        let visibleActiveSubAgents: [ActiveSubAgent]
        let visibleActiveTools: [ActiveTool]
    }

    static func dedupe(
        messages: [ChatMessage],
        toolHistory: [ToolHistoryEntry],
        activeSubAgents: [ActiveSubAgent],
        activeTools: [ActiveTool]
    ) -> DisplayState {
        let representedIDs = collectRepresentedToolIDs(from: messages)

        let visibleActiveSubAgents = activeSubAgents.filter { subAgent in
            !representedIDs.subAgentIDs.contains(subAgent.id)
        }

        let visibleActiveTools = activeTools.filter { tool in
            !representedIDs.toolIDs.contains(tool.id)
        }

        let visibleToolHistory = toolHistory.compactMap { entry -> ToolHistoryEntry? in
            if let subAgent = entry.subAgent {
                if representedIDs.subAgentIDs.contains(subAgent.id) {
                    return nil
                }
                return entry
            }

            guard !entry.tools.isEmpty else { return nil }
            let filteredTools = entry.tools.filter { tool in
                !representedIDs.toolIDs.contains(tool.id)
            }

            guard !filteredTools.isEmpty else { return nil }
            guard filteredTools.count != entry.tools.count else { return entry }

            return ToolHistoryEntry(
                id: entry.id,
                tools: filteredTools,
                subAgent: nil,
                afterMessageIndex: entry.afterMessageIndex
            )
        }

        return DisplayState(
            visibleToolHistory: visibleToolHistory,
            visibleActiveSubAgents: visibleActiveSubAgents,
            visibleActiveTools: visibleActiveTools
        )
    }

    private struct RepresentedToolIDs {
        var subAgentIDs: Set<String> = []
        var toolIDs: Set<String> = []
    }

    private static func collectRepresentedToolIDs(from messages: [ChatMessage]) -> RepresentedToolIDs {
        var represented = RepresentedToolIDs()

        for message in messages {
            for content in message.content {
                switch content {
                case .subAgentActivity(let activity):
                    let parentID = normalizedID(activity.parentToolUseId)
                    if let parentID {
                        represented.subAgentIDs.insert(parentID)
                    }

                case .toolUse(let toolUse):
                    if let toolUseID = normalizedID(toolUse.toolUseId) {
                        represented.toolIDs.insert(toolUseID)
                    }

                default:
                    continue
                }
            }
        }

        return represented
    }

    private static func normalizedID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
