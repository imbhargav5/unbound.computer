//
//  ClaudeMessageParser.swift
//  unbound-macos
//
//  Parses daemon-stored Claude message JSON into ChatMessage content.
//

import Foundation

struct ClaudeMessageParser {
    private static let maxRawJSONDepth = 4

    static func parseMessage(_ daemonMessage: DaemonMessage) -> ChatMessage? {
        guard let content = daemonMessage.content, !content.isEmpty else { return nil }

        let messageDate = daemonMessage.date ?? Date()

        guard let contentData = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .user,
                text: content,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )
        }

        let payload = resolvedPayload(from: json)
        guard let type = messageType(from: payload) else {
            let fallback = fallbackText(from: content)
            guard !fallback.isEmpty else { return nil }
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .system,
                text: fallback,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )
        }

        switch type {
        case "assistant":
            guard let messageContent = parseClaudeContent(payload) else { return nil }
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .assistant,
                content: messageContent,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )

        case "user":
            guard let messageContent = parseUserContent(payload) else { return nil }
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .user,
                content: messageContent,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )

        case "result":
            if let errorText = parseResultError(payload) {
                return ChatMessage(
                    id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                    role: .system,
                    text: "Error: \(errorText)",
                    timestamp: messageDate,
                    sequenceNumber: daemonMessage.sequenceNumber
                )
            }
            return nil

        case "system":
            return nil

        default:
            let fallback = fallbackText(from: content)
            guard !fallback.isEmpty else { return nil }
            return ChatMessage(
                id: UUID(uuidString: daemonMessage.id) ?? UUID(),
                role: .system,
                text: fallback,
                timestamp: messageDate,
                sequenceNumber: daemonMessage.sequenceNumber
            )
        }
    }

    static func parseClaudeContent(_ json: [String: Any]) -> [MessageContent]? {
        let payload = resolvedPayload(from: json)
        guard let type = messageType(from: payload) else { return nil }

        switch type {
        case "assistant":
            guard let message = payload["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else {
                return nil
            }

            var content: [MessageContent] = []
            var subAgentIndexById: [String: Int] = [:]
            var pendingToolsByParent: [String: [ToolUse]] = [:]
            var pendingParentOrder: [String] = []
            let messageParent = payload["parent_tool_use_id"] as? String

            for block in contentBlocks {
                if let blockType = block["type"] as? String {
                    switch blockType {
                    case "text":
                        if let text = sanitizedText(block["text"] as? String) {
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
                                    subAgent.tools = mergeTools(existing: subAgent.tools, incoming: pendingTools)
                                }

                                if let existingIndex = subAgentIndexById[id],
                                   case .subAgentActivity(let existingSubAgent) = content[existingIndex] {
                                    content[existingIndex] = .subAgentActivity(
                                        mergedSubAgent(existing: existingSubAgent, incoming: subAgent)
                                    )
                                } else {
                                    content.append(.subAgentActivity(subAgent))
                                    subAgentIndexById[id] = content.count - 1
                                }
                                continue
                            }

                            if let parentId = parentToolUseId {
                                if let index = subAgentIndexById[parentId],
                                   case .subAgentActivity(var subAgent) = content[index] {
                                    subAgent.tools = mergeTools(existing: subAgent.tools, incoming: [toolUse])
                                    content[index] = .subAgentActivity(subAgent)
                                } else {
                                    let existingPending = pendingToolsByParent[parentId, default: []]
                                    pendingToolsByParent[parentId] = mergeTools(existing: existingPending, incoming: [toolUse])
                                    if !pendingParentOrder.contains(parentId) {
                                        pendingParentOrder.append(parentId)
                                    }
                                }
                            } else {
                                appendOrUpdateStandaloneTool(toolUse, to: &content)
                            }
                        }

                    default:
                        break
                    }
                }
            }

            for parentId in pendingParentOrder {
                guard let pendingTools = pendingToolsByParent[parentId] else { continue }
                for tool in pendingTools {
                    appendOrUpdateStandaloneTool(tool, to: &content)
                }
            }

            return content.isEmpty ? nil : content

        case "user":
            return parseUserContent(payload)

        case "result":
            if let errorText = parseResultError(payload) {
                return [.error(ErrorContent(message: errorText))]
            }
            return nil

        default:
            return nil
        }
    }

    static func resolvedPayload(from payload: [String: Any]) -> [String: Any] {
        var current = payload
        var depth = 0

        while depth < maxRawJSONDepth,
              let wrappedRawJSON = current["raw_json"] as? String,
              let wrappedData = wrappedRawJSON.data(using: .utf8),
              let wrappedPayload = try? JSONSerialization.jsonObject(with: wrappedData) as? [String: Any] {
            current = wrappedPayload
            depth += 1
        }

        return current
    }

    static func messageType(from payload: [String: Any]) -> String? {
        guard let type = payload["type"] as? String else { return nil }
        return type.lowercased()
    }

    static func toolResultUpdates(fromUserPayload payload: [String: Any]) -> [(toolUseId: String, status: ToolStatus)] {
        guard let message = payload["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return []
        }

        var updates: [(toolUseId: String, status: ToolStatus)] = []
        updates.reserveCapacity(contentBlocks.count)

        for block in contentBlocks {
            guard let blockType = block["type"] as? String,
                  blockType == "tool_result",
                  let toolUseId = block["tool_use_id"] as? String else {
                continue
            }

            let isError = block["is_error"] as? Bool ?? false
            updates.append((toolUseId: toolUseId, status: isError ? .failed : .completed))
        }

        return updates
    }

    private static func parseUserContent(_ payload: [String: Any]) -> [MessageContent]? {
        if let message = sanitizedText(payload["message"] as? String) {
            return [.text(TextContent(text: message))]
        }

        guard let message = payload["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return nil
        }

        var content: [MessageContent] = []
        for block in contentBlocks {
            guard let blockType = block["type"] as? String else { continue }
            switch blockType {
            case "text":
                if let text = sanitizedText(block["text"] as? String) {
                    content.append(.text(TextContent(text: text)))
                }

            case "tool_result":
                for text in visibleToolResultTextFragments(from: block) {
                    content.append(.text(TextContent(text: text)))
                }

            default:
                break
            }
        }

        return content.isEmpty ? nil : content
    }

    private static func parseResultError(_ payload: [String: Any]) -> String? {
        let isError = payload["is_error"] as? Bool ?? false
        guard isError else { return nil }
        return sanitizedText(payload["result"] as? String)
    }

    private static func fallbackText(from content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func visibleToolResultTextFragments(from block: [String: Any]) -> [String] {
        if let content = block["content"] as? String,
           let text = sanitizedText(content),
           !looksLikeProtocolArtifact(text) {
            return [text]
        }

        if let contentArray = block["content"] as? [[String: Any]] {
            return contentArray.compactMap { item in
                guard let text = sanitizedText(item["text"] as? String),
                      !looksLikeProtocolArtifact(text) else {
                    return nil
                }
                return text
            }
        }

        return []
    }

    private static func looksLikeProtocolArtifact(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            return false
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = (json["type"] as? String)?.lowercased() else {
            return false
        }

        let protocolTypes: Set<String> = ["user", "assistant", "system", "result", "tool_result"]
        return protocolTypes.contains(type)
    }

    private static func appendOrUpdateStandaloneTool(_ toolUse: ToolUse, to content: inout [MessageContent]) {
        let key = toolDedupKey(for: toolUse)

        if let existingIndex = content.firstIndex(where: { messageContent in
            guard case .toolUse(let existing) = messageContent else { return false }
            return toolDedupKey(for: existing) == key
        }) {
            content[existingIndex] = .toolUse(toolUse)
        } else {
            content.append(.toolUse(toolUse))
        }
    }

    private static func mergedSubAgent(existing: SubAgentActivity, incoming: SubAgentActivity) -> SubAgentActivity {
        SubAgentActivity(
            id: existing.id,
            parentToolUseId: existing.parentToolUseId,
            subagentType: mergedSubagentType(existing: existing.subagentType, incoming: incoming.subagentType),
            description: mergedDescription(existing: existing.description, incoming: incoming.description),
            tools: mergeTools(existing: existing.tools, incoming: incoming.tools),
            status: incoming.status,
            result: incoming.result ?? existing.result
        )
    }

    private static func mergedDescription(existing: String, incoming: String) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty else { return existing }
        return incoming
    }

    private static func mergedSubagentType(existing: String, incoming: String) -> String {
        if isPlaceholderSubagentType(existing), !isPlaceholderSubagentType(incoming) {
            return incoming
        }
        return existing
    }

    private static func isPlaceholderSubagentType(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown" || normalized == "general-purpose"
            || normalized == "general purpose" || normalized == "general"
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
}
