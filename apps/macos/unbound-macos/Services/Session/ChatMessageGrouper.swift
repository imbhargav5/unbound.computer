//
//  ChatMessageGrouper.swift
//  unbound-macos
//
//  Groups tool_use messages under their parent sub-agent across messages.
//

import Foundation

struct ChatMessageGrouper {

    static func groupSubAgentTools(messages: [ChatMessage]) -> [ChatMessage] {
        let subAgentParents = collectSubAgentParents(messages: messages)
        guard !subAgentParents.isEmpty else { return messages }

        var result: [ChatMessage] = []
        var anchorByParent: [String: Anchor] = [:]
        var pendingToolsByParent: [String: [ToolUse]] = [:]

        for message in messages {
            var newMessage = message
            var newContent: [MessageContent] = []

            for content in message.content {
                switch content {
                case .subAgentActivity(var subAgent):
                    if let pending = pendingToolsByParent.removeValue(forKey: subAgent.parentToolUseId) {
                        subAgent.tools = mergeTools(existing: subAgent.tools, incoming: pending)
                    }
                    newContent.append(.subAgentActivity(subAgent))
                    anchorByParent[subAgent.parentToolUseId] = Anchor(
                        messageIndex: result.count,
                        contentIndex: newContent.count - 1
                    )

                case .toolUse(let toolUse):
                    if let parentId = toolUse.parentToolUseId,
                       subAgentParents.contains(parentId) {
                        if let anchor = anchorByParent[parentId] {
                            append(toolUse: toolUse, to: anchor, in: &result)
                        } else {
                            let existingPending = pendingToolsByParent[parentId, default: []]
                            pendingToolsByParent[parentId] = mergeTools(existing: existingPending, incoming: [toolUse])
                        }
                        continue
                    }
                    newContent.append(.toolUse(toolUse))

                default:
                    newContent.append(content)
                }
            }

            newMessage.content = newContent
            if !newContent.isEmpty {
                result.append(newMessage)
            }
        }

        return result
    }

    private static func collectSubAgentParents(messages: [ChatMessage]) -> Set<String> {
        var parents: Set<String> = []
        for message in messages {
            for content in message.content {
                if case .subAgentActivity(let subAgent) = content {
                    parents.insert(subAgent.parentToolUseId)
                }
            }
        }
        return parents
    }

    private static func append(toolUse: ToolUse, to anchor: Anchor, in messages: inout [ChatMessage]) {
        guard messages.indices.contains(anchor.messageIndex) else { return }
        var message = messages[anchor.messageIndex]
        guard message.content.indices.contains(anchor.contentIndex) else { return }
        if case .subAgentActivity(var subAgent) = message.content[anchor.contentIndex] {
            subAgent.tools = mergeTools(existing: subAgent.tools, incoming: [toolUse])
            message.content[anchor.contentIndex] = .subAgentActivity(subAgent)
            messages[anchor.messageIndex] = message
        }
    }

    private static func mergeTools(existing: [ToolUse], incoming: [ToolUse]) -> [ToolUse] {
        guard !incoming.isEmpty else { return existing }

        var merged = existing
        var indexByKey: [String: Int] = [:]

        for (index, tool) in existing.enumerated() {
            indexByKey[toolDedupKey(for: tool)] = index
        }

        for tool in incoming {
            let key = toolDedupKey(for: tool)
            if let existingIndex = indexByKey[key] {
                merged[existingIndex] = tool
            } else {
                indexByKey[key] = merged.count
                merged.append(tool)
            }
        }

        return merged
    }

    private static func toolDedupKey(for tool: ToolUse) -> String {
        if let toolUseId = tool.toolUseId, !toolUseId.isEmpty {
            return "id:\(toolUseId)"
        }

        return "fallback:\(tool.parentToolUseId ?? "")|\(tool.toolName)|\(tool.input ?? "")"
    }

    private struct Anchor {
        let messageIndex: Int
        let contentIndex: Int
    }
}
