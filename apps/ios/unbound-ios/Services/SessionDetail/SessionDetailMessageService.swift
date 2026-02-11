//
//  SessionDetailMessageService.swift
//  unbound-ios
//
//  Service that loads, decrypts, and maps session detail messages.
//

import Foundation
import Logging

private let sessionDetailServiceLogger = Logger(label: "app.session-detail.service")

protocol SessionSecretResolving {
    func joinCodingSession(_ sessionId: UUID) async throws -> String
}

extension CodingSessionViewerService: SessionSecretResolving {}

struct SessionDetailLoadResult {
    let messages: [Message]
    let decryptedMessageCount: Int
}

protocol SessionDetailMessageLoading {
    func loadMessages(sessionId: UUID) async throws -> SessionDetailLoadResult
}

final class SessionDetailMessageService: SessionDetailMessageLoading {
    private let remoteSource: SessionDetailMessageRemoteSource
    private let secretResolver: SessionSecretResolving

    init(
        remoteSource: SessionDetailMessageRemoteSource = SupabaseSessionDetailMessageRemoteSource(),
        secretResolver: SessionSecretResolving = CodingSessionViewerService()
    ) {
        self.remoteSource = remoteSource
        self.secretResolver = secretResolver
    }

    func loadMessages(sessionId: UUID) async throws -> SessionDetailLoadResult {
        let rows = try await remoteSource.fetchEncryptedRows(sessionId: sessionId)
        sessionDetailServiceLogger.debug(
            "Fetched \(rows.count) encrypted rows for session \(sessionId.uuidString.lowercased())"
        )
        guard !rows.isEmpty else {
            return SessionDetailLoadResult(messages: [], decryptedMessageCount: 0)
        }

        let sessionSecret: String
        do {
            sessionSecret = try await secretResolver.joinCodingSession(sessionId)
        } catch {
            sessionDetailServiceLogger.error(
                "Failed to resolve session secret for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
            )
            throw SessionDetailMessageError.secretResolutionFailed
        }

        let sessionKey: Data
        do {
            sessionKey = try SessionSecretFormat.parseKey(secret: sessionSecret)
        } catch {
            throw SessionDetailMessageError.secretResolutionFailed
        }

        do {
            var mapped: [(sequenceNumber: Int, message: Message)] = []
            mapped.reserveCapacity(rows.count)

            for row in rows {
                let plaintext: String
                do {
                    plaintext = try row.decrypt(sessionKey: sessionKey)
                } catch {
                    sessionDetailServiceLogger.error(
                        "Failed to decrypt row id=\(row.id), seq=\(row.sequenceNumber), session=\(sessionId.uuidString.lowercased()), encrypted_len=\(row.contentEncrypted.count), nonce_len=\(row.contentNonce.count): \(error.localizedDescription)"
                    )
                    throw SessionDetailMessageError.decryptFailed
                }

                guard let entry = SessionMessagePayloadParser.timelineEntry(from: plaintext) else {
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
                decryptedMessageCount: rows.count
            )
        } catch let error as SessionDetailMessageError {
            sessionDetailServiceLogger.error(
                "Failed during message decrypt/map for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
            )
            throw error
        } catch {
            sessionDetailServiceLogger.error(
                "Failed during message decrypt/map for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
            )
            throw SessionDetailMessageError.payloadParseFailed
        }
    }

    private func groupSubAgentTools(messages: [Message]) -> [Message] {
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

    private func collectSubAgentParents(messages: [Message]) -> Set<String> {
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

    private func append(toolUse: SessionToolUse, to anchor: GroupAnchor, in messages: inout [Message]) {
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

    private func append(toolUse: SessionToolUse, toLocalIndex index: Int, in blocks: inout [SessionContentBlock]) {
        guard blocks.indices.contains(index),
              case .subAgentActivity(var activity) = blocks[index] else {
            return
        }

        activity.tools = mergeTools(existing: activity.tools, incoming: [toolUse])
        blocks[index] = .subAgentActivity(activity)
    }

    private func merge(subAgentActivity incoming: SessionSubAgentActivity, to anchor: GroupAnchor, in messages: inout [Message]) {
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

    private func merge(subAgentActivity incoming: SessionSubAgentActivity, toLocalIndex index: Int, in blocks: inout [SessionContentBlock]) {
        guard blocks.indices.contains(index),
              case .subAgentActivity(let existing) = blocks[index] else {
            return
        }

        blocks[index] = .subAgentActivity(mergedActivity(existing: existing, incoming: incoming))
    }

    private func mergedActivity(
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

    private func mergedDescription(existing: String, incoming: String) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty else { return existing }
        return incoming
    }

    private func mergedSubagentType(existing: String, incoming: String) -> String {
        if isPlaceholderSubagentType(existing), !isPlaceholderSubagentType(incoming) {
            return incoming
        }
        return existing
    }

    private func isPlaceholderSubagentType(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown" || normalized == "general-purpose"
            || normalized == "general purpose" || normalized == "general"
    }

    private func mergeTools(existing: [SessionToolUse], incoming: [SessionToolUse]) -> [SessionToolUse] {
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

    private func toolDedupKey(for tool: SessionToolUse) -> String {
        if let toolUseId = tool.toolUseId, !toolUseId.isEmpty {
            return "id:\(toolUseId)"
        }

        return "fallback:\(tool.parentToolUseId ?? "")|\(tool.toolName)|\(tool.summary)"
    }

    private func rebuiltMessage(from message: Message, content: String, parsedContent: [SessionContentBlock]) -> Message {
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

    private func content(from blocks: [SessionContentBlock]) -> String {
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
