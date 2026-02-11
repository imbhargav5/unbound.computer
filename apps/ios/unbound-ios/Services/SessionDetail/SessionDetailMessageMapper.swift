//
//  SessionDetailMessageMapper.swift
//  unbound-ios
//
//  Shared mapper for turning plaintext session rows into UI timeline messages.
//

import CryptoKit
import Foundation

struct SessionDetailPlaintextMessageRow {
    let id: String
    let sequenceNumber: Int
    let createdAt: Date?
    let content: String

    var stableUUID: UUID {
        if let uuid = UUID(uuidString: id) {
            return uuid
        }

        let digest = SHA256.hash(data: Data("\(id)-\(sequenceNumber)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum SessionDetailMessageMapper {
    static func mapRows(
        _ rows: [SessionDetailPlaintextMessageRow],
        totalMessageCount: Int? = nil
    ) -> SessionDetailLoadResult {
        var mapped: [(sequenceNumber: Int, message: Message)] = []
        mapped.reserveCapacity(rows.count)

        for row in rows {
            guard let entry = SessionMessagePayloadParser.timelineEntry(from: row.content) else {
                continue
            }

            mapped.append((
                sequenceNumber: row.sequenceNumber,
                message: Message(
                    id: row.stableUUID,
                    content: entry.content,
                    role: entry.role,
                    timestamp: row.createdAt ?? Date(timeIntervalSince1970: 0),
                    isStreaming: false,
                    parsedContent: entry.blocks.isEmpty ? nil : entry.blocks
                )
            ))
        }

        let sortedMessages = mapped
            .sorted { lhs, rhs in lhs.sequenceNumber < rhs.sequenceNumber }
            .map(\.message)
        let groupedMessages = groupSubAgentTools(messages: sortedMessages)

        return SessionDetailLoadResult(
            messages: groupedMessages,
            decryptedMessageCount: totalMessageCount ?? rows.count
        )
    }

    private static func groupSubAgentTools(messages: [Message]) -> [Message] {
        let subAgentParents = collectSubAgentParents(messages: messages)
        guard !subAgentParents.isEmpty else { return messages }

        var result: [Message] = []
        var anchorByParent: [String: GroupAnchor] = [:]
        var pendingToolsByParent: [String: [SessionToolUse]] = [:]

        for message in messages {
            guard let parsedContent = message.parsedContent, !parsedContent.isEmpty else {
                result.append(message)
                continue
            }

            var newBlocks: [SessionContentBlock] = []
            var localIndexByParent: [String: Int] = [:]

            for block in parsedContent {
                switch block {
                case .subAgentActivity(var activity):
                    if let pending = pendingToolsByParent.removeValue(forKey: activity.parentToolUseId) {
                        activity.tools = mergeTools(existing: activity.tools, incoming: pending)
                    }
                    activity.tools = mergeTools(existing: [], incoming: activity.tools)

                    if let localIndex = localIndexByParent[activity.parentToolUseId] {
                        merge(subAgentActivity: activity, toLocalIndex: localIndex, in: &newBlocks)
                    } else if let anchor = anchorByParent[activity.parentToolUseId] {
                        merge(subAgentActivity: activity, to: anchor, in: &result)
                    } else {
                        newBlocks.append(.subAgentActivity(activity))
                        localIndexByParent[activity.parentToolUseId] = newBlocks.count - 1
                    }

                case .toolUse(let toolUse):
                    if let parentId = toolUse.parentToolUseId,
                       subAgentParents.contains(parentId) {
                        if let localIndex = localIndexByParent[parentId] {
                            append(toolUse: toolUse, toLocalIndex: localIndex, in: &newBlocks)
                        } else if let anchor = anchorByParent[parentId] {
                            append(toolUse: toolUse, to: anchor, in: &result)
                        } else {
                            pendingToolsByParent[parentId, default: []].append(toolUse)
                        }
                        continue
                    }
                    newBlocks.append(.toolUse(toolUse))

                default:
                    newBlocks.append(block)
                }
            }

            if newBlocks.isEmpty {
                continue
            }

            let rebuilt = rebuiltMessage(
                from: message,
                content: content(from: newBlocks),
                parsedContent: newBlocks
            )
            result.append(rebuilt)

            let messageIndex = result.count - 1
            for (parentId, blockIndex) in localIndexByParent {
                anchorByParent[parentId] = GroupAnchor(
                    messageIndex: messageIndex,
                    blockIndex: blockIndex
                )
            }
        }

        return result
    }

    private static func collectSubAgentParents(messages: [Message]) -> Set<String> {
        var parents: Set<String> = []

        for message in messages {
            guard let blocks = message.parsedContent else { continue }
            for block in blocks {
                if case .subAgentActivity(let activity) = block {
                    parents.insert(activity.parentToolUseId)
                }
            }
        }

        return parents
    }

    private static func append(toolUse: SessionToolUse, to anchor: GroupAnchor, in messages: inout [Message]) {
        guard messages.indices.contains(anchor.messageIndex) else { return }
        let message = messages[anchor.messageIndex]
        guard var parsed = message.parsedContent,
              parsed.indices.contains(anchor.blockIndex) else {
            return
        }

        guard case .subAgentActivity(var activity) = parsed[anchor.blockIndex] else {
            return
        }

        activity.tools = mergeTools(existing: activity.tools, incoming: [toolUse])
        parsed[anchor.blockIndex] = .subAgentActivity(activity)

        messages[anchor.messageIndex] = rebuiltMessage(
            from: message,
            content: content(from: parsed),
            parsedContent: parsed
        )
    }

    private static func append(toolUse: SessionToolUse, toLocalIndex index: Int, in blocks: inout [SessionContentBlock]) {
        guard blocks.indices.contains(index),
              case .subAgentActivity(var activity) = blocks[index] else {
            return
        }

        activity.tools = mergeTools(existing: activity.tools, incoming: [toolUse])
        blocks[index] = .subAgentActivity(activity)
    }

    private static func merge(subAgentActivity incoming: SessionSubAgentActivity, to anchor: GroupAnchor, in messages: inout [Message]) {
        guard messages.indices.contains(anchor.messageIndex) else { return }
        let message = messages[anchor.messageIndex]
        guard var parsed = message.parsedContent,
              parsed.indices.contains(anchor.blockIndex),
              case .subAgentActivity(let existing) = parsed[anchor.blockIndex] else {
            return
        }

        parsed[anchor.blockIndex] = .subAgentActivity(mergedActivity(existing: existing, incoming: incoming))

        messages[anchor.messageIndex] = rebuiltMessage(
            from: message,
            content: content(from: parsed),
            parsedContent: parsed
        )
    }

    private static func merge(subAgentActivity incoming: SessionSubAgentActivity, toLocalIndex index: Int, in blocks: inout [SessionContentBlock]) {
        guard blocks.indices.contains(index),
              case .subAgentActivity(let existing) = blocks[index] else {
            return
        }

        blocks[index] = .subAgentActivity(mergedActivity(existing: existing, incoming: incoming))
    }

    private static func mergedActivity(
        existing: SessionSubAgentActivity,
        incoming: SessionSubAgentActivity
    ) -> SessionSubAgentActivity {
        let resolvedSubagentType = mergedSubagentType(
            existing: existing.subagentType,
            incoming: incoming.subagentType
        )
        let resolvedDescription = mergedDescription(
            existing: existing.description,
            incoming: incoming.description
        )

        return SessionSubAgentActivity(
            id: existing.id,
            parentToolUseId: existing.parentToolUseId,
            subagentType: resolvedSubagentType,
            description: resolvedDescription,
            tools: mergeTools(existing: existing.tools, incoming: incoming.tools)
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

    private static func mergeTools(existing: [SessionToolUse], incoming: [SessionToolUse]) -> [SessionToolUse] {
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

    private static func toolDedupKey(for tool: SessionToolUse) -> String {
        if let toolUseId = tool.toolUseId, !toolUseId.isEmpty {
            return "id:\(toolUseId)"
        }

        return "fallback:\(tool.parentToolUseId ?? "")|\(tool.toolName)|\(tool.summary)"
    }

    private static func rebuiltMessage(from message: Message, content: String, parsedContent: [SessionContentBlock]) -> Message {
        Message(
            id: message.id,
            content: content,
            role: message.role,
            timestamp: message.timestamp,
            codeBlocks: message.codeBlocks,
            isStreaming: message.isStreaming,
            richContent: message.richContent,
            parsedContent: parsedContent
        )
    }

    private static func content(from blocks: [SessionContentBlock]) -> String {
        blocks.compactMap { block in
            switch block {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .error(let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .toolUse, .subAgentActivity:
                return nil
            }
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GroupAnchor {
    let messageIndex: Int
    let blockIndex: Int
}
