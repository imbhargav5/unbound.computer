import ClaudeConversationTimeline
import CryptoKit
import Foundation

enum ClaudeTimelineChatMessageMapper {
    private static let protocolTypes: Set<String> = [
        "assistant", "mcq_response_command", "output_chunk", "result", "stream_event",
        "streaming_generating", "streaming_thinking", "system", "terminal_output",
        "tool_result", "user", "user_confirmation_command", "user_prompt_command"
    ]
    private static let toolEnvelopeBlockTypes: Set<String> = ["tool_result", "tool_use"]

    static func mapEntries(_ entries: [ClaudeConversationTimelineEntry]) -> [ChatMessage] {
        let mappedMessages: [ChatMessage] = entries.compactMap { entry -> ChatMessage? in
            let content = mapBlocks(entry.blocks)
            guard !content.isEmpty else { return nil }

            let role: MessageRole
            switch entry.role {
            case .user:
                role = .user
            case .assistant:
                role = .assistant
            case .system, .result, .unknown:
                role = .system
            }

            if role == .user, !hasVisibleUserText(content) {
                return nil
            }

            return ChatMessage(
                id: stableUUID(for: entry.id),
                role: role,
                content: content,
                timestamp: entry.createdAt ?? Date(),
                isStreaming: false,
                sequenceNumber: entry.sequence ?? 0
            )
        }

        // Re-associate child tool calls with their Task parent across message boundaries.
        // This keeps the UI reactive when tool events arrive out of order.
        return ChatMessageGrouper.groupSubAgentTools(messages: mappedMessages)
    }

    private static func mapBlocks(_ blocks: [ClaudeConversationBlock]) -> [MessageContent] {
        var mapped: [MessageContent] = []

        for block in blocks {
            switch block {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    mapped.append(.text(TextContent(text: trimmed)))
                }

            case .toolCall(let tool):
                if let todoList = makeTodoList(from: tool) {
                    mapped.append(.todoList(todoList))
                } else {
                    mapped.append(.toolUse(makeToolUse(from: tool)))
                }

            case .subAgent(let subAgent):
                mapped.append(.subAgentActivity(makeSubAgent(from: subAgent)))

            case .result(let result):
                if result.isError, let message = result.text {
                    mapped.append(.error(ErrorContent(message: message)))
                }

            case .error(let message):
                mapped.append(.error(ErrorContent(message: message)))

            case .compactBoundary:
                mapped.append(.text(TextContent(text: "Compact boundary")))

            case .unknown:
                continue
            }
        }

        return mapped
    }

    private static func makeTodoList(from tool: ClaudeToolCallBlock) -> TodoList? {
        guard tool.name == "TodoWrite",
              let input = tool.input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let todosValue = (json["todos"] as? [[String: Any]])
            ?? ((json["input"] as? [String: Any])?["todos"] as? [[String: Any]])
        guard let todosValue, !todosValue.isEmpty else {
            return nil
        }

        let items = todosValue.compactMap { todo -> TodoItem? in
            guard let content = todo["content"] as? String else { return nil }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let rawStatus = (todo["status"] as? String)?.lowercased()
            let status: TodoStatus
            switch rawStatus {
            case "completed":
                status = .completed
            case "in_progress":
                status = .inProgress
            default:
                status = .pending
            }

            return TodoItem(content: trimmed, status: status)
        }

        guard !items.isEmpty else { return nil }
        return TodoList(items: items)
    }

    private static func makeToolUse(from tool: ClaudeToolCallBlock) -> ToolUse {
        ToolUse(
            toolUseId: tool.toolUseId,
            parentToolUseId: tool.parentToolUseId,
            toolName: tool.name,
            input: tool.input,
            output: tool.resultText,
            status: mapStatus(tool.status)
        )
    }

    private static func makeSubAgent(from subAgent: ClaudeSubAgentBlock) -> SubAgentActivity {
        let tools = subAgent.tools.map { makeToolUse(from: $0) }
        return SubAgentActivity(
            parentToolUseId: subAgent.parentToolUseId,
            subagentType: subAgent.subagentType,
            description: subAgent.description,
            tools: tools,
            status: mapStatus(subAgent.status),
            result: subAgent.result
        )
    }

    private static func mapStatus(_ status: ClaudeToolCallStatus) -> ToolStatus {
        switch status {
        case .running:
            return .running
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }

    private static func stableUUID(for value: String) -> UUID {
        if let uuid = UUID(uuidString: value) {
            return uuid
        }

        let digest = SHA256.hash(data: Data(value.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func hasVisibleUserText(_ content: [MessageContent]) -> Bool {
        content.contains { block in
            guard case .text(let textContent) = block else { return false }
            let trimmed = textContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return !looksLikeProtocolArtifact(trimmed) && !looksLikeSerializedToolEnvelope(trimmed)
        }
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

        return protocolTypes.contains(type)
    }

    private static func looksLikeSerializedToolEnvelope(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            return false
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let normalized = trimmed.lowercased()
            let hasTypeMarker = normalized.contains("\"type\"")
            let hasToolMarkers = normalized.contains("\"tool_use\"")
                || normalized.contains("\"tool_result\"")
                || normalized.contains("\"tool_use_id\"")
                || normalized.contains("\"raw_json\"")
            return hasTypeMarker && hasToolMarkers
        }

        if json["raw_json"] as? String != nil {
            return true
        }

        if let type = (json["type"] as? String)?.lowercased(),
           protocolTypes.contains(type) {
            return true
        }

        if let message = json["message"] as? [String: Any],
           let contentBlocks = message["content"] as? [[String: Any]] {
            return contentBlocks.contains { block in
                guard let blockType = (block["type"] as? String)?.lowercased() else {
                    return false
                }
                return toolEnvelopeBlockTypes.contains(blockType)
            }
        }

        return false
    }
}
