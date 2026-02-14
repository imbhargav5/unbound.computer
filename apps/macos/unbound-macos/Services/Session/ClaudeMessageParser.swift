//
//  ClaudeMessageParser.swift
//  unbound-macos
//
//  Parses daemon-stored Claude message JSON into ChatMessage content.
//

import Foundation

struct ClaudeMessageParser {

    static func parseMessage(_ daemonMessage: DaemonMessage) -> ChatMessage? {
        guard let content = daemonMessage.content, !content.isEmpty else { return nil }

        let messageDate = daemonMessage.date ?? Date()

        guard let contentData = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let type = json["type"] as? String else {
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .user,
                text: content,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )
        }

        switch type {
        case "assistant":
            guard let messageContent = parseClaudeContent(json) else { return nil }
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .assistant,
                content: messageContent,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )
        case "result":
            let isError = json["is_error"] as? Bool ?? false
            if isError, let errorText = json["result"] as? String {
                return ChatMessage(
                    id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                    role: .system,
                    text: "Error: \(errorText)",
                    timestamp: messageDate,
                    sequenceNumber: daemonMessage.sequenceNumber
                )
            }
            return nil
        case "system", "user":
            return nil
        default:
            return nil
        }
    }

    static func parseClaudeContent(_ json: [String: Any]) -> [MessageContent]? {
        guard let type = json["type"] as? String else { return nil }

        switch type {
        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else {
                return nil
            }

            var content: [MessageContent] = []
            var subAgentIndexById: [String: Int] = [:]
            var pendingToolsByParent: [String: [ToolUse]] = [:]
            var pendingOrder: [ToolUse] = []
            let messageParent = json["parent_tool_use_id"] as? String

            for block in contentBlocks {
                if let blockType = block["type"] as? String {
                    switch blockType {
                    case "text":
                        if let text = block["text"] as? String {
                            content.append(.text(TextContent(text: text)))
                        }
                    case "tool_use":
                        if let id = block["id"] as? String,
                           let name = block["name"] as? String {
                            let inputDict = block["input"] as? [String: Any]
                            let inputJson = inputDict.flatMap { dict in
                                try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
                            }.flatMap { String(data: $0, encoding: .utf8) }
                            let parentToolUseId = (block["parent_tool_use_id"] as? String) ?? messageParent

                            let toolUse = ToolUse(
                                toolUseId: id,
                                parentToolUseId: parentToolUseId,
                                toolName: name,
                                input: inputJson,
                                status: .completed
                            )

                            if name == "Task" {
                                let subagentType = inputDict?["subagent_type"] as? String ?? "unknown"
                                let description = inputDict?["description"] as? String ?? ""

                                var subAgent = SubAgentActivity(
                                    parentToolUseId: id,
                                    subagentType: subagentType,
                                    description: description,
                                    tools: [],
                                    status: .completed
                                )

                                if let pendingTools = pendingToolsByParent.removeValue(forKey: id) {
                                    subAgent.tools.append(contentsOf: pendingTools)
                                }

                                content.append(.subAgentActivity(subAgent))
                                subAgentIndexById[id] = content.count - 1
                                continue
                            }

                            if let parentId = parentToolUseId {
                                if let index = subAgentIndexById[parentId],
                                   case .subAgentActivity(var subAgent) = content[index] {
                                    subAgent.tools.append(toolUse)
                                    content[index] = .subAgentActivity(subAgent)
                                } else {
                                    pendingToolsByParent[parentId, default: []].append(toolUse)
                                    pendingOrder.append(toolUse)
                                }
                            } else {
                                content.append(.toolUse(toolUse))
                            }
                        }
                    default:
                        break
                    }
                }
            }

            if !pendingOrder.isEmpty {
                for tool in pendingOrder {
                    guard let parentId = tool.parentToolUseId,
                          pendingToolsByParent[parentId] != nil else {
                        continue
                    }
                    content.append(.toolUse(tool))
                }
            }
            return content.isEmpty ? nil : content

        case "user":
            guard let message = json["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else {
                return nil
            }

            var content: [MessageContent] = []
            for block in contentBlocks {
                if let blockType = block["type"] as? String, blockType == "tool_result" {
                    if let toolContent = block["content"] as? String {
                        content.append(.text(TextContent(text: toolContent)))
                    }
                }
            }
            return content.isEmpty ? nil : content

        default:
            return nil
        }
    }
}
