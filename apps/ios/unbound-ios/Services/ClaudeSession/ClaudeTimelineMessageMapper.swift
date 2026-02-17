import ClaudeConversationTimeline
import CryptoKit
import Foundation

enum ClaudeTimelineMessageMapper {
    static func mapEntries(_ entries: [ClaudeConversationTimelineEntry]) -> [Message] {
        entries.compactMap { entry in
            let blocks = mapBlocks(entry.blocks)
            guard !blocks.isEmpty else { return nil }

            let content = blocks.compactMap { block -> String? in
                if case .text(let text) = block {
                    return text
                }
                return nil
            }.joined(separator: "\n")

            let role: Message.MessageRole
            switch entry.role {
            case .user:
                role = .user
            case .assistant:
                role = .assistant
            case .system, .result, .unknown:
                role = .system
            }

            return Message(
                id: stableUUID(for: entry.id),
                content: content,
                role: role,
                timestamp: entry.createdAt ?? Date(),
                parsedContent: blocks
            )
        }
    }

    private static func mapBlocks(_ blocks: [ClaudeConversationBlock]) -> [SessionContentBlock] {
        var mapped: [SessionContentBlock] = []

        for block in blocks {
            switch block {
            case .text(let text):
                mapped.append(.text(text))

            case .toolCall(let tool):
                mapped.append(.toolUse(makeToolUse(from: tool)))

            case .subAgent(let subAgent):
                mapped.append(.subAgentActivity(makeSubAgent(from: subAgent)))

            case .result(let result):
                if result.isError, let message = result.text {
                    mapped.append(.error(message))
                }

            case .error(let message):
                mapped.append(.error(message))

            case .compactBoundary, .unknown:
                continue
            }
        }

        return mapped
    }

    private static func makeToolUse(from tool: ClaudeToolCallBlock) -> SessionToolUse {
        SessionToolUse(
            toolUseId: tool.toolUseId,
            parentToolUseId: tool.parentToolUseId,
            toolName: tool.name,
            summary: toolSummary(name: tool.name, input: tool.input)
        )
    }

    private static func makeSubAgent(from subAgent: ClaudeSubAgentBlock) -> SessionSubAgentActivity {
        let tools = subAgent.tools.map { makeToolUse(from: $0) }
        return SessionSubAgentActivity(
            parentToolUseId: subAgent.parentToolUseId,
            subagentType: subAgent.subagentType,
            description: subAgent.description,
            tools: tools
        )
    }

    private static func toolSummary(name: String, input: String?) -> String {
        guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return name
        }

        if let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let path = json["file_path"] as? String ?? json["path"] as? String {
                return "\(name) \(path)"
            }
            if let command = json["command"] as? String {
                return "\(name) \(truncate(command))"
            }
            if let query = json["query"] as? String {
                return "\(name) \(truncate(query))"
            }
            if let description = json["description"] as? String {
                return "\(name) \(truncate(description))"
            }
        }

        return "\(name) \(truncate(input))"
    }

    private static func truncate(_ value: String, limit: Int = 120) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return trimmed[..<index] + "…"
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
}
