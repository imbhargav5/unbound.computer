import Foundation

public final class ClaudeConversationTimelineParser {
    private let maxRawJSONDepth = 4
    private static let protocolTypes: Set<String> = [
        "assistant", "mcq_response_command", "output_chunk", "result", "stream_event",
        "streaming_generating", "streaming_thinking", "system", "terminal_output",
        "tool_result", "user", "user_confirmation_command", "user_prompt_command"
    ]
    private static let userCommandTypes: Set<String> = [
        "user_prompt_command",
        "user_confirmation_command",
        "mcq_response_command",
    ]
    private static let toolEnvelopeBlockTypes: Set<String> = ["tool_result", "tool_use"]
    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601PlainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private var timeline: [ClaudeConversationTimelineEntry] = []

    public init() {}

    @discardableResult
    public func ingest(rawJSON: String) -> [ClaudeConversationTimelineEntry] {
        guard let data = rawJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return timeline
        }

        ingest(payload: json)
        return timeline
    }

    @discardableResult
    public func ingest(payload: [String: Any]) -> [ClaudeConversationTimelineEntry] {
        let resolved = resolvedPayload(from: payload)
        let normalized = mergedEnvelopeMetadata(payload: payload, resolvedPayload: resolved)
        guard let type = messageType(from: normalized) else { return timeline }

        switch type {
        case "assistant":
            if let entry = parseAssistant(payload: normalized) {
                upsert(entry: entry)
            }

        case "user", "user_prompt_command", "user_confirmation_command", "mcq_response_command":
            if let entry = parseUser(payload: normalized) {
                upsert(entry: entry)
            }
            applyToolResultUpdates(from: normalized)

        case "system":
            if let entry = parseSystem(payload: normalized) {
                upsert(entry: entry)
            }

        case "result":
            if let entry = parseResult(payload: normalized) {
                upsert(entry: entry)
            }

        case "stream_event":
            handleStreamEvent(payload: normalized)

        default:
            break
        }

        return timeline
    }

    private func mergedEnvelopeMetadata(payload: [String: Any], resolvedPayload: [String: Any]) -> [String: Any] {
        var merged = resolvedPayload

        if parseSequence(merged) == nil {
            if let sequenceNumber = integerValue(payload["sequence_number"]) {
                merged["sequence_number"] = sequenceNumber
            } else if let sequence = integerValue(payload["sequence"]) {
                merged["sequence"] = sequence
            }
        }

        if parseDate(merged["created_at"]) == nil, let createdAt = payload["created_at"] {
            merged["created_at"] = createdAt
        }

        return merged
    }

    public func currentTimeline() -> [ClaudeConversationTimelineEntry] {
        timeline
    }

    private func parseAssistant(payload: [String: Any]) -> ClaudeConversationTimelineEntry? {
        guard let message = payload["message"] as? [String: Any] else { return nil }
        let contentBlocks = (message["content"] as? [[String: Any]]) ?? []

        var blocks: [ClaudeConversationBlock] = []
        var subAgentIndexById: [String: Int] = [:]
        var pendingToolsByParent: [String: [ClaudeToolCallBlock]] = [:]
        var pendingParentOrder: [String] = []
        let messageParent = payload["parent_tool_use_id"] as? String

        for block in contentBlocks {
            guard let blockType = (block["type"] as? String)?.lowercased() else { continue }

            switch blockType {
            case "text":
                if let text = sanitizedText(block["text"] as? String) {
                    blocks.append(.text(text))
                }

            case "tool_use":
                guard let toolId = block["id"] as? String,
                      let name = block["name"] as? String else {
                    continue
                }

                let inputDict = block["input"] as? [String: Any]
                let inputJson = inputDict.flatMap { dict in
                    try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
                }.flatMap { String(data: $0, encoding: .utf8) }

                let parentToolUseId = (block["parent_tool_use_id"] as? String) ?? messageParent
                let toolUse = ClaudeToolCallBlock(
                    toolUseId: toolId,
                    parentToolUseId: parentToolUseId,
                    name: name,
                    input: inputJson,
                    status: .running,
                    resultText: nil
                )

                if name == "Task" {
                    let subagentType = (inputDict?["subagent_type"] as? String) ?? "unknown"
                    let description = (inputDict?["description"] as? String) ?? ""
                    var subAgent = ClaudeSubAgentBlock(
                        parentToolUseId: toolId,
                        subagentType: subagentType,
                        description: description,
                        tools: [],
                        status: .running,
                        result: nil
                    )

                    if let pendingTools = pendingToolsByParent.removeValue(forKey: toolId) {
                        subAgent = subAgent.with(tools: mergeTools(existing: subAgent.tools, incoming: pendingTools),
                                                 status: subAgent.status,
                                                 result: subAgent.result)
                    }

                    if let existingIndex = subAgentIndexById[toolId],
                       case .subAgent(let existingSubAgent) = blocks[existingIndex] {
                        blocks[existingIndex] = .subAgent(mergeSubAgent(existing: existingSubAgent, incoming: subAgent))
                    } else {
                        blocks.append(.subAgent(subAgent))
                        subAgentIndexById[toolId] = blocks.count - 1
                    }
                    continue
                }

                if let parentId = parentToolUseId {
                    if let index = subAgentIndexById[parentId],
                       case .subAgent(let subAgent) = blocks[index] {
                        let mergedTools = mergeTools(existing: subAgent.tools, incoming: [toolUse])
                        blocks[index] = .subAgent(subAgent.with(tools: mergedTools, status: subAgent.status, result: subAgent.result))
                    } else {
                        let existingPending = pendingToolsByParent[parentId, default: []]
                        pendingToolsByParent[parentId] = mergeTools(existing: existingPending, incoming: [toolUse])
                        if !pendingParentOrder.contains(parentId) {
                            pendingParentOrder.append(parentId)
                        }
                    }
                } else {
                    appendOrUpdateStandaloneTool(toolUse, to: &blocks)
                }

            default:
                break
            }
        }

        for parentId in pendingParentOrder {
            guard let pendingTools = pendingToolsByParent[parentId] else { continue }
            for tool in pendingTools {
                appendOrUpdateStandaloneTool(tool, to: &blocks)
            }
        }

        guard !blocks.isEmpty else { return nil }

        return ClaudeConversationTimelineEntry(
            id: canonicalId(from: payload, fallbackPrefix: "assistant"),
            role: .assistant,
            blocks: blocks,
            createdAt: parseDate(payload["created_at"]),
            sequence: parseSequence(payload),
            sourceType: "assistant"
        )
    }

    private func parseUser(payload: [String: Any]) -> ClaudeConversationTimelineEntry? {
        let sourceType = messageType(from: payload) ?? "user"
        if shouldSuppressUserPayload(payload, sourceType: sourceType) {
            return nil
        }

        var blocks: [ClaudeConversationBlock] = []
        var sawEnvelopeOnly = false

        if let message = payload["message"] as? [String: Any],
           let contentBlocks = message["content"] as? [[String: Any]] {
            for block in contentBlocks {
                guard let blockType = (block["type"] as? String)?.lowercased() else { continue }

                switch blockType {
                case "text":
                    if block["tool_use_id"] != nil {
                        sawEnvelopeOnly = true
                        continue
                    }

                    if let text = sanitizedText(block["text"] as? String),
                       !looksLikeProtocolArtifact(text),
                       !looksLikeSerializedToolEnvelope(text) {
                        blocks.append(.text(text))
                    }

                case "tool_result":
                    sawEnvelopeOnly = true

                case "tool_use":
                    sawEnvelopeOnly = true

                default:
                    if block["tool_use_id"] != nil {
                        sawEnvelopeOnly = true
                        continue
                    }

                    if let text = extractVisibleText(from: block),
                       !looksLikeProtocolArtifact(text),
                       !looksLikeSerializedToolEnvelope(text) {
                        blocks.append(.text(text))
                    }
                }
            }

            if blocks.isEmpty, sawEnvelopeOnly {
                return nil
            }
        }

        if blocks.isEmpty,
           (Self.userCommandTypes.contains(sourceType) || sourceType == "user"),
           let text = extractVisibleText(from: payload),
           !looksLikeProtocolArtifact(text),
           !looksLikeSerializedToolEnvelope(text) {
            blocks.append(.text(text))
        }

        guard !blocks.isEmpty else { return nil }

        return ClaudeConversationTimelineEntry(
            id: canonicalId(from: payload, fallbackPrefix: "user"),
            role: .user,
            blocks: blocks,
            createdAt: parseDate(payload["created_at"]),
            sequence: parseSequence(payload),
            sourceType: sourceType
        )
    }

    private func parseSystem(payload: [String: Any]) -> ClaudeConversationTimelineEntry? {
        let subtype = (payload["subtype"] as? String)?.lowercased()
        guard subtype == "compact_boundary" else { return nil }

        return ClaudeConversationTimelineEntry(
            id: canonicalId(from: payload, fallbackPrefix: "system"),
            role: .system,
            blocks: [.compactBoundary],
            createdAt: parseDate(payload["created_at"]),
            sequence: parseSequence(payload),
            sourceType: "system"
        )
    }

    private func parseResult(payload: [String: Any]) -> ClaudeConversationTimelineEntry? {
        let isError = payload["is_error"] as? Bool ?? false
        let text = sanitizedText(payload["result"] as? String)
        let permissionDenials = (payload["permission_denials"] as? [String]) ?? []
        let metrics = parseResultMetrics(from: payload)

        let block = ClaudeResultBlock(
            isError: isError,
            text: text,
            permissionDenials: permissionDenials,
            metrics: metrics
        )
        return ClaudeConversationTimelineEntry(
            id: canonicalId(from: payload, fallbackPrefix: "result"),
            role: .result,
            blocks: [.result(block)],
            createdAt: parseDate(payload["created_at"]),
            sequence: parseSequence(payload),
            sourceType: "result"
        )
    }

    private func handleStreamEvent(payload: [String: Any]) {
        guard let messageId = (payload["message_id"] as? String) ?? (payload["id"] as? String) else {
            return
        }

        let deltaText = ((payload["delta"] as? [String: Any])?["text"] as? String)
            ?? (payload["text"] as? String)
        guard let update = sanitizedText(deltaText) else { return }

        let entryId = "stream-\(messageId)"
        var blocks: [ClaudeConversationBlock] = []

        if let existingIndex = timeline.firstIndex(where: { $0.id == entryId }) {
            let existing = timeline[existingIndex]
            let existingText = existing.blocks.compactMap { block -> String? in
                if case .text(let text) = block { return text }
                return nil
            }.joined()
            let mergedText = existingText + update
            blocks = [.text(mergedText)]
            let updated = ClaudeConversationTimelineEntry(
                id: entryId,
                role: .assistant,
                blocks: blocks,
                createdAt: existing.createdAt,
                sequence: existing.sequence,
                sourceType: "stream_event"
            )
            timeline[existingIndex] = updated
        } else {
            blocks = [.text(update)]
            let entry = ClaudeConversationTimelineEntry(
                id: entryId,
                role: .assistant,
                blocks: blocks,
                createdAt: parseDate(payload["created_at"]),
                sequence: parseSequence(payload),
                sourceType: "stream_event"
            )
            upsert(entry: entry)
        }
    }

    private func applyToolResultUpdates(from payload: [String: Any]) {
        guard let message = payload["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return
        }

        for block in contentBlocks {
            guard let blockType = (block["type"] as? String)?.lowercased(),
                  blockType == "tool_result",
                  let toolUseId = block["tool_use_id"] as? String else {
                continue
            }

            let isError = block["is_error"] as? Bool ?? false
            let status: ClaudeToolCallStatus = isError ? .failed : .completed
            let resultText = sanitizedText(block["content"] as? String)

            updateTool(withId: toolUseId, status: status, resultText: resultText)
        }
    }

    private func updateTool(withId toolUseId: String, status: ClaudeToolCallStatus, resultText: String?) {
        for (entryIndex, entry) in timeline.enumerated() {
            var updatedBlocks = entry.blocks
            var changed = false

            for (blockIndex, block) in entry.blocks.enumerated() {
                switch block {
                case .toolCall(let tool) where tool.toolUseId == toolUseId:
                    updatedBlocks[blockIndex] = .toolCall(tool.with(status: status, resultText: resultText))
                    changed = true
                case .subAgent(let subAgent):
                    let updatedTools = subAgent.tools.map { tool in
                        guard tool.toolUseId == toolUseId else { return tool }
                        return tool.with(status: status, resultText: resultText)
                    }
                    if updatedTools != subAgent.tools {
                        updatedBlocks[blockIndex] = .subAgent(subAgent.with(tools: updatedTools, status: subAgent.status, result: subAgent.result))
                        changed = true
                    }
                default:
                    break
                }
            }

            if changed {
                let updatedEntry = ClaudeConversationTimelineEntry(
                    id: entry.id,
                    role: entry.role,
                    blocks: updatedBlocks,
                    createdAt: entry.createdAt,
                    sequence: entry.sequence,
                    sourceType: entry.sourceType
                )
                timeline[entryIndex] = updatedEntry
            }
        }
    }

    private func upsert(entry: ClaudeConversationTimelineEntry) {
        if let index = timeline.firstIndex(where: { $0.id == entry.id }) {
            let existing = timeline[index]
            if existing.role == .assistant, entry.role == .assistant {
                timeline[index] = mergeAssistantEntry(existing: existing, incoming: entry)
            } else {
                timeline[index] = entry
            }
        } else {
            timeline.append(entry)
        }

        timeline.sort(by: entrySort(lhs:rhs:))
    }

    private func mergeAssistantEntry(
        existing: ClaudeConversationTimelineEntry,
        incoming: ClaudeConversationTimelineEntry
    ) -> ClaudeConversationTimelineEntry {
        ClaudeConversationTimelineEntry(
            id: existing.id,
            role: .assistant,
            blocks: mergeAssistantBlocks(existing: existing.blocks, incoming: incoming.blocks),
            createdAt: incoming.createdAt ?? existing.createdAt,
            sequence: incoming.sequence ?? existing.sequence,
            sourceType: incoming.sourceType
        )
    }

    private func mergeAssistantBlocks(
        existing: [ClaudeConversationBlock],
        incoming: [ClaudeConversationBlock]
    ) -> [ClaudeConversationBlock] {
        let existingText = existing.compactMap { block -> String? in
            guard case .text(let text) = block else { return nil }
            return text
        }
        let incomingText = incoming.compactMap { block -> String? in
            guard case .text(let text) = block else { return nil }
            return text
        }
        let mergedText = incomingText.isEmpty ? existingText : incomingText

        var subAgentsByParent: [String: ClaudeSubAgentBlock] = [:]
        var toolsByKey: [String: ClaudeToolCallBlock] = [:]
        var otherByKey: [String: ClaudeConversationBlock] = [:]

        for block in existing {
            switch block {
            case .subAgent(let subAgent):
                subAgentsByParent[subAgent.parentToolUseId] = subAgent
            case .toolCall(let tool):
                toolsByKey[toolDedupKey(for: tool)] = tool
            default:
                if let key = assistantOtherBlockKey(for: block) {
                    otherByKey[key] = block
                }
            }
        }

        for block in incoming {
            switch block {
            case .subAgent(let subAgent):
                if let existingSubAgent = subAgentsByParent[subAgent.parentToolUseId] {
                    subAgentsByParent[subAgent.parentToolUseId] = mergeSubAgent(
                        existing: existingSubAgent,
                        incoming: subAgent
                    )
                } else {
                    subAgentsByParent[subAgent.parentToolUseId] = subAgent
                }
            case .toolCall(let tool):
                toolsByKey[toolDedupKey(for: tool)] = tool
            default:
                if let key = assistantOtherBlockKey(for: block) {
                    otherByKey[key] = block
                }
            }
        }

        var orderedTokens: [AssistantMergeToken] = []
        var seenTokens: Set<AssistantMergeToken> = []

        for block in existing + incoming {
            guard let token = assistantMergeToken(for: block) else { continue }
            if seenTokens.insert(token).inserted {
                orderedTokens.append(token)
            }
        }

        var mergedBlocks: [ClaudeConversationBlock] = []
        for token in orderedTokens {
            switch token {
            case .text:
                mergedBlocks.append(contentsOf: mergedText.map { .text($0) })
            case .subAgent(let parentToolUseId):
                if let subAgent = subAgentsByParent[parentToolUseId] {
                    mergedBlocks.append(.subAgent(subAgent))
                }
            case .tool(let key):
                if let tool = toolsByKey[key] {
                    mergedBlocks.append(.toolCall(tool))
                }
            case .other(let key):
                if let block = otherByKey[key] {
                    mergedBlocks.append(block)
                }
            }
        }

        if mergedBlocks.isEmpty {
            return incoming
        }

        return mergedBlocks
    }

    private func entrySort(lhs: ClaudeConversationTimelineEntry, rhs: ClaudeConversationTimelineEntry) -> Bool {
        if let lhsSeq = lhs.sequence, let rhsSeq = rhs.sequence, lhsSeq != rhsSeq {
            return lhsSeq < rhsSeq
        }
        if let lhsDate = lhs.createdAt, let rhsDate = rhs.createdAt, lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.id < rhs.id
    }

    private func resolvedPayload(from payload: [String: Any]) -> [String: Any] {
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

    private func messageType(from payload: [String: Any]) -> String? {
        guard let type = payload["type"] as? String else { return nil }
        return type.lowercased()
    }

    private func hasParentToolUseId(_ payload: [String: Any]) -> Bool {
        guard let parentToolUseId = payload["parent_tool_use_id"] as? String else {
            return false
        }
        return !parentToolUseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func shouldSuppressUserPayload(_ payload: [String: Any], sourceType: String) -> Bool {
        if sourceType == "user", hasParentToolUseId(payload) {
            return true
        }
        return false
    }

    private func canonicalId(from payload: [String: Any], fallbackPrefix: String) -> String {
        if let message = payload["message"] as? [String: Any],
           let messageId = message["id"] as? String {
            return messageId
        }
        if let id = payload["id"] as? String {
            return id
        }
        if let eventId = payload["event_id"] as? String {
            return eventId
        }
        return "\(fallbackPrefix)-\(UUID().uuidString)"
    }

    private func parseSequence(_ payload: [String: Any]) -> Int? {
        if let sequence = integerValue(payload["sequence_number"]) { return sequence }
        if let sequence = integerValue(payload["sequence"]) { return sequence }
        return nil
    }

    private func parseDate(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let timestamp = value as? TimeInterval {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let dateString = value as? String {
            let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Self.iso8601FractionalFormatter.date(from: trimmed)
                ?? Self.iso8601PlainFormatter.date(from: trimmed) {
                return parsed
            }
            if let seconds = TimeInterval(trimmed) {
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let stringValue = value as? String {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double { return doubleValue }
        if let number = value as? NSNumber { return number.doubleValue }
        if let stringValue = value as? String {
            return Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func parseResultMetrics(from payload: [String: Any]) -> ClaudeResultMetrics? {
        let usage = parseResultUsage(from: payload["usage"])
        let metrics = ClaudeResultMetrics(
            stopReason: sanitizedText(payload["stop_reason"] as? String),
            subtype: sanitizedText(payload["subtype"] as? String),
            numTurns: integerValue(payload["num_turns"]),
            totalCostUSD: doubleValue(payload["total_cost_usd"]) ?? doubleValue(payload["cost_usd"]),
            durationMs: integerValue(payload["duration_ms"]),
            durationApiMs: integerValue(payload["duration_api_ms"]),
            usage: usage
        )

        if metrics.stopReason == nil,
           metrics.subtype == nil,
           metrics.numTurns == nil,
           metrics.totalCostUSD == nil,
           metrics.durationMs == nil,
           metrics.durationApiMs == nil,
           metrics.usage == nil {
            return nil
        }

        return metrics
    }

    private func parseResultUsage(from value: Any?) -> ClaudeResultUsage? {
        guard let usagePayload = value as? [String: Any] else { return nil }

        let usage = ClaudeResultUsage(
            inputTokens: integerValue(usagePayload["input_tokens"]),
            outputTokens: integerValue(usagePayload["output_tokens"]),
            cacheReadInputTokens: integerValue(usagePayload["cache_read_input_tokens"]),
            cacheCreationInputTokens: integerValue(usagePayload["cache_creation_input_tokens"])
        )

        if usage.inputTokens == nil,
           usage.outputTokens == nil,
           usage.cacheReadInputTokens == nil,
           usage.cacheCreationInputTokens == nil {
            return nil
        }

        return usage
    }

    private func sanitizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func looksLikeProtocolArtifact(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            return false
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = (json["type"] as? String)?.lowercased() else {
            return false
        }

        return Self.protocolTypes.contains(type)
    }

    private func extractVisibleText(from payload: [String: Any]) -> String? {
        if let text = sanitizedText(payload["text"] as? String) { return text }
        if let message = sanitizedText(payload["message"] as? String) { return message }

        if let message = payload["message"] as? [String: Any] {
            if let text = sanitizedText(message["text"] as? String) { return text }

            if let content = message["content"] {
                let fragments = textFragments(from: content)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !fragments.isEmpty {
                    return fragments.joined(separator: "\n")
                }
            }
        }

        if let content = sanitizedText(payload["content"] as? String) { return content }

        if let content = payload["content"] {
            let fragments = textFragments(from: content)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !fragments.isEmpty {
                return fragments.joined(separator: "\n")
            }
        }

        return nil
    }

    private func textFragments(from value: Any) -> [String] {
        if let text = value as? String {
            return text.isEmpty ? [] : [text]
        }

        if let array = value as? [Any] {
            return array.flatMap { item in
                if let text = item as? String {
                    return text.isEmpty ? [] : [text]
                }
                if let dict = item as? [String: Any] {
                    if let text = dict["text"] as? String, !text.isEmpty {
                        return [text]
                    }
                    if let content = dict["content"] as? String, !content.isEmpty {
                        return [content]
                    }
                }
                return []
            }
        }

        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String, !text.isEmpty {
                return [text]
            }
            if let content = dict["content"] as? String, !content.isEmpty {
                return [content]
            }
        }

        return []
    }

    private func looksLikeSerializedToolEnvelope(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            return false
        }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["raw_json"] as? String != nil {
                return true
            }

            if let type = (json["type"] as? String)?.lowercased(),
               Self.protocolTypes.contains(type) {
                return true
            }

            if let message = json["message"] as? [String: Any],
               let contentBlocks = message["content"] as? [[String: Any]] {
                return contentBlocks.contains { block in
                    guard let blockType = (block["type"] as? String)?.lowercased() else {
                        return false
                    }
                    return Self.toolEnvelopeBlockTypes.contains(blockType)
                }
            }

            return false
        }

        let normalized = trimmed.lowercased()
        let hasTypeMarker = normalized.contains("\"type\"")
        let hasToolMarkers = normalized.contains("\"tool_use\"")
            || normalized.contains("\"tool_result\"")
            || normalized.contains("\"tool_use_id\"")
            || normalized.contains("\"raw_json\"")
        return hasTypeMarker && hasToolMarkers
    }

    private enum AssistantMergeToken: Hashable {
        case text
        case subAgent(String)
        case tool(String)
        case other(String)
    }

    private func assistantMergeToken(for block: ClaudeConversationBlock) -> AssistantMergeToken? {
        switch block {
        case .text:
            return .text
        case .subAgent(let subAgent):
            return .subAgent(subAgent.parentToolUseId)
        case .toolCall(let tool):
            return .tool(toolDedupKey(for: tool))
        case .result, .error, .compactBoundary, .unknown:
            guard let key = assistantOtherBlockKey(for: block) else { return nil }
            return .other(key)
        }
    }

    private func assistantOtherBlockKey(for block: ClaudeConversationBlock) -> String? {
        switch block {
        case .result:
            return "result"
        case .error:
            return "error"
        case .compactBoundary:
            return "compact_boundary"
        case .unknown(let value):
            return "unknown:\(value)"
        default:
            return nil
        }
    }

    private func appendOrUpdateStandaloneTool(_ toolUse: ClaudeToolCallBlock, to blocks: inout [ClaudeConversationBlock]) {
        let key = toolDedupKey(for: toolUse)
        if let index = blocks.firstIndex(where: { block in
            guard case .toolCall(let existing) = block else { return false }
            return toolDedupKey(for: existing) == key
        }) {
            blocks[index] = .toolCall(toolUse)
        } else {
            blocks.append(.toolCall(toolUse))
        }
    }

    private func mergeSubAgent(existing: ClaudeSubAgentBlock, incoming: ClaudeSubAgentBlock) -> ClaudeSubAgentBlock {
        let mergedTools = mergeTools(existing: existing.tools, incoming: incoming.tools)
        let mergedType = mergedSubagentType(existing: existing.subagentType, incoming: incoming.subagentType)
        let mergedDescription = mergedDescription(existing: existing.description, incoming: incoming.description)
        return ClaudeSubAgentBlock(
            parentToolUseId: existing.parentToolUseId,
            subagentType: mergedType,
            description: mergedDescription,
            tools: mergedTools,
            status: incoming.status,
            result: incoming.result ?? existing.result
        )
    }

    private func mergedDescription(existing: String, incoming: String) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedIncoming.isEmpty ? existing : incoming
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

    private func mergeTools(existing: [ClaudeToolCallBlock], incoming: [ClaudeToolCallBlock]) -> [ClaudeToolCallBlock] {
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

    private func toolDedupKey(for tool: ClaudeToolCallBlock) -> String {
        if let toolUseId = tool.toolUseId, !toolUseId.isEmpty {
            return "id:\(toolUseId)"
        }
        return "fallback:\(tool.parentToolUseId ?? "")|\(tool.name)|\(tool.input ?? "")"
    }
}
