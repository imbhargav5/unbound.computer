//
//  SessionMessagePayloadParser.swift
//  unbound-ios
//
//  Shared parser for decrypted session message payloads.
//

import Foundation

struct SessionTimelineEntry {
    let role: Message.MessageRole
    let content: String
    let blocks: [SessionContentBlock]
}

enum SessionMessagePayloadParser {
    private static let maxRawJSONDepth = 4
    private static let protocolTypes: Set<String> = ["user", "assistant", "system", "result", "tool_result"]

    static func timelineEntry(from plaintext: String) -> SessionTimelineEntry? {
        guard let payload = resolvedPayload(from: plaintext) else {
            let text = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SessionTimelineEntry(role: .user, content: text, blocks: [.text(text)])
        }

        return buildTimelineEntry(from: payload, plaintext: plaintext)
    }

    static func role(from plaintext: String) -> Message.MessageRole {
        guard let payload = jsonPayload(from: plaintext) else { return .system }
        let resolved = resolvedPayload(from: payload)

        if let parsedRole = explicitRole(from: resolved) {
            return parsedRole
        }

        if let type = messageType(from: resolved) {
            return role(forType: type)
        }

        return .system
    }

    static func displayText(from plaintext: String) -> String {
        guard let payload = jsonPayload(from: plaintext) else { return plaintext }
        let resolved = resolvedPayload(from: payload)

        if let text = extractVisibleText(from: resolved) {
            return text
        }

        if let type = messageType(from: resolved),
           type == "terminal_output",
           let stream = resolved["stream"] as? String,
           let content = resolved["content"] as? String {
            return "[\(stream)] \(content)"
        }

        if let data = try? JSONSerialization.data(withJSONObject: resolved, options: []),
           let compact = String(data: data, encoding: .utf8) {
            return compact
        }

        return plaintext
    }

    // MARK: - Content Block Parsing

    static func parseContentBlocks(from plaintext: String) -> [SessionContentBlock] {
        guard let payload = resolvedPayload(from: plaintext) else {
            let text = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [.text(text)]
        }

        guard let type = messageType(from: payload) else {
            return fallbackBlocks(from: plaintext)
        }

        switch type {
        case "assistant":
            return parseAssistantBlocks(payload)
        case "user", "user_prompt_command", "user_confirmation_command", "mcq_response_command":
            return parseUserBlocks(payload)
        case "result":
            return parseResultBlocks(payload)
        default:
            return fallbackBlocks(from: plaintext)
        }
    }

    private static func resolvedPayload(from plaintext: String) -> [String: Any]? {
        guard let payload = jsonPayload(from: plaintext) else { return nil }
        return resolvedPayload(from: payload)
    }

    private static func resolvedPayload(from payload: [String: Any]) -> [String: Any] {
        var current = payload
        var depth = 0

        while depth < maxRawJSONDepth,
              let wrappedRawJSON = current["raw_json"] as? String,
              let wrappedPayload = jsonPayload(from: wrappedRawJSON) {
            current = wrappedPayload
            depth += 1
        }

        return current
    }

    private static func parseAssistantBlocks(_ payload: [String: Any]) -> [SessionContentBlock] {
        guard let blocks = parseAssistantStructuredBlocks(payload) else {
            return fallbackBlocks(from: payload)
        }
        return blocks
    }

    private static func parseAssistantTimelineBlocks(_ payload: [String: Any]) -> [SessionContentBlock] {
        guard let blocks = parseAssistantStructuredBlocks(payload) else {
            guard let fallbackText = extractVisibleText(from: payload) else {
                return []
            }
            return [.text(fallbackText)]
        }

        if blocks.isEmpty, let fallbackText = extractVisibleText(from: payload) {
            return [.text(fallbackText)]
        }

        return blocks.filter(\.isVisibleContent)
    }

    private static func parseAssistantStructuredBlocks(_ payload: [String: Any]) -> [SessionContentBlock]? {
        guard let message = payload["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return nil
        }

        var blocks: [SessionContentBlock] = []
        var subAgentIndexByParent: [String: Int] = [:]
        var pendingToolsByParent: [String: [SessionToolUse]] = [:]
        var pendingParentOrder: [String] = []
        let messageParent = payload["parent_tool_use_id"] as? String

        for block in contentBlocks {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = sanitizedText(block["text"] as? String) {
                    blocks.append(.text(text))
                }

            case "tool_use":
                guard let name = block["name"] as? String else { continue }
                let inputDict = block["input"] as? [String: Any]
                let toolUseId = block["id"] as? String
                let parentToolUseId = (block["parent_tool_use_id"] as? String) ?? messageParent
                let toolUse = makeSessionToolUse(
                    toolName: name,
                    input: inputDict,
                    toolUseId: toolUseId,
                    parentToolUseId: parentToolUseId
                )

                if name == "Task", let taskId = toolUseId {
                    let subagentType = (inputDict?["subagent_type"] as? String) ?? "general-purpose"
                    let description = (inputDict?["description"] as? String) ?? ""
                    var activity = SessionSubAgentActivity(
                        parentToolUseId: taskId,
                        subagentType: subagentType,
                        description: description
                    )

                    if let pendingTools = pendingToolsByParent.removeValue(forKey: taskId) {
                        activity.tools = mergeTools(existing: activity.tools, incoming: pendingTools)
                    }

                    if let existingIndex = subAgentIndexByParent[taskId],
                       case .subAgentActivity(let existingActivity) = blocks[existingIndex] {
                        blocks[existingIndex] = .subAgentActivity(
                            mergedSubAgentActivity(existing: existingActivity, incoming: activity)
                        )
                    } else {
                        blocks.append(.subAgentActivity(activity))
                        subAgentIndexByParent[taskId] = blocks.count - 1
                    }
                    continue
                }

                if let parentId = parentToolUseId {
                    if let index = subAgentIndexByParent[parentId],
                       case .subAgentActivity(var activity) = blocks[index] {
                        activity.tools = mergeTools(existing: activity.tools, incoming: [toolUse])
                        blocks[index] = .subAgentActivity(activity)
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
            for toolUse in pendingTools {
                appendOrUpdateStandaloneTool(toolUse, to: &blocks)
            }
        }

        return blocks
    }

    private static func makeSessionToolUse(
        toolName: String,
        input: [String: Any]?,
        toolUseId: String?,
        parentToolUseId: String?
    ) -> SessionToolUse {
        SessionToolUse(
            toolUseId: toolUseId,
            parentToolUseId: parentToolUseId,
            toolName: toolName,
            summary: toolSummary(name: toolName, input: input)
        )
    }

    private static func parseUserBlocks(_ payload: [String: Any]) -> [SessionContentBlock] {
        // User prompt commands with a direct message string
        if let message = sanitizedText(payload["message"] as? String) {
            return [.text(message)]
        }

        guard let message = payload["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return fallbackBlocks(from: payload)
        }

        var blocks: [SessionContentBlock] = []

        for block in contentBlocks {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = sanitizedText(block["text"] as? String) {
                    blocks.append(.text(text))
                }
            case "tool_result":
                for text in visibleToolResultTextFragments(from: block) {
                    blocks.append(.text(text))
                }
            default:
                break
            }
        }

        return blocks
    }

    private static func parseResultBlocks(_ payload: [String: Any]) -> [SessionContentBlock] {
        let isError = payload["is_error"] as? Bool ?? false
        if let result = sanitizedText(payload["result"] as? String) {
            return isError ? [.error(result)] : []
        }
        return []
    }

    private static func fallbackBlocks(from plaintext: String) -> [SessionContentBlock] {
        let text = displayText(from: plaintext)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.text(text)]
    }

    private static func fallbackBlocks(from payload: [String: Any]) -> [SessionContentBlock] {
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            return fallbackBlocks(from: jsonString)
        }
        return []
    }

    private static func toolSummary(name: String, input: [String: Any]?) -> String {
        guard let input else { return name }

        switch name {
        case "Read":
            if let filePath = input["file_path"] as? String {
                return "Read \(shortenPath(filePath))"
            }
        case "Write":
            if let filePath = input["file_path"] as? String {
                return "Write \(shortenPath(filePath))"
            }
        case "Edit":
            if let filePath = input["file_path"] as? String {
                return "Edit \(shortenPath(filePath))"
            }
        case "Bash":
            if let command = input["command"] as? String {
                let truncated = command.count > 60
                    ? String(command.prefix(60)) + "..."
                    : command
                return truncated
            }
        case "Grep":
            if let pattern = input["pattern"] as? String {
                return "Grep \(pattern)"
            }
        case "Glob":
            if let pattern = input["pattern"] as? String {
                return "Glob \(pattern)"
            }
        case "WebSearch":
            if let query = input["query"] as? String {
                return "Search: \(query)"
            }
        case "WebFetch":
            if let url = input["url"] as? String {
                return "Fetch \(url)"
            }
        case "Task":
            if let description = input["description"] as? String {
                return description
            }
        case "NotebookEdit":
            if let notebookPath = input["notebook_path"] as? String {
                return "Edit \(shortenPath(notebookPath))"
            }
        default:
            break
        }

        return name
    }

    private static func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count <= 2 {
            return path
        }
        return String(components.suffix(2).joined(separator: "/"))
    }

    // MARK: - Timeline Entry Parsing

    private static func buildTimelineEntry(from payload: [String: Any], plaintext: String) -> SessionTimelineEntry? {
        let type = messageType(from: payload)

        switch type {
        case "assistant":
            let blocks = parseAssistantTimelineBlocks(payload)
            guard blocks.contains(where: \.isVisibleContent) else { return nil }
            let role = resolvedRole(from: payload, fallbackType: "assistant")
            return SessionTimelineEntry(
                role: role,
                content: timelineContent(from: blocks),
                blocks: blocks
            )

        case "user":
            return buildUserTimelineEntry(from: payload)

        case "result":
            let isError = payload["is_error"] as? Bool ?? false
            guard isError,
                  let result = payload["result"] as? String else {
                return nil
            }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return SessionTimelineEntry(
                role: .system,
                content: trimmed,
                blocks: [.error(trimmed)]
            )

        case "terminal_output":
            guard let stream = payload["stream"] as? String,
                  let content = payload["content"] as? String else {
                return nil
            }
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedContent.isEmpty else { return nil }
            let terminalText = "[\(stream)] \(trimmedContent)"
            return SessionTimelineEntry(
                role: .assistant,
                content: terminalText,
                blocks: [.text(terminalText)]
            )

        case "user_prompt_command", "user_confirmation_command", "mcq_response_command":
            return buildUserCommandTimelineEntry(from: payload)

        case "system":
            return nil

        case .some:
            return buildLegacyTimelineEntry(from: payload, plaintext: plaintext)

        case .none:
            return buildLegacyTimelineEntry(from: payload, plaintext: plaintext)
        }
    }

    private static func buildLegacyTimelineEntry(from payload: [String: Any], plaintext _: String) -> SessionTimelineEntry? {
        guard let visibleText = extractVisibleText(from: payload) else {
            return nil
        }

        let role = resolvedRole(from: payload, fallbackType: payload["type"] as? String)
        guard role != .system else { return nil }

        return SessionTimelineEntry(
            role: role,
            content: visibleText,
            blocks: [.text(visibleText)]
        )
    }

    private static func buildUserTimelineEntry(from payload: [String: Any]) -> SessionTimelineEntry? {
        if let message = payload["message"] as? [String: Any],
           let contentBlocks = message["content"] as? [[String: Any]] {
            var userTextBlocks: [SessionContentBlock] = []
            var sawProtocolArtifact = false

            for block in contentBlocks {
                guard let blockType = block["type"] as? String else { continue }

                switch blockType {
                case "text":
                    if let text = sanitizedText(block["text"] as? String) {
                        userTextBlocks.append(.text(text))
                    }
                case "tool_result":
                    let visibleFragments = visibleToolResultTextFragments(from: block)
                    if visibleFragments.isEmpty {
                        sawProtocolArtifact = true
                    } else {
                        for fragment in visibleFragments {
                            userTextBlocks.append(.text(fragment))
                        }
                    }
                case "tool_use":
                    sawProtocolArtifact = true
                default:
                    if let text = extractVisibleText(from: block),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        userTextBlocks.append(.text(text))
                    }
                }
            }

            if !userTextBlocks.isEmpty {
                return SessionTimelineEntry(
                    role: .user,
                    content: timelineContent(from: userTextBlocks),
                    blocks: userTextBlocks
                )
            }

            if sawProtocolArtifact {
                return nil
            }
        }

        guard let text = extractVisibleText(from: payload),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return SessionTimelineEntry(
            role: .user,
            content: text,
            blocks: [.text(text)]
        )
    }

    private static func buildUserCommandTimelineEntry(from payload: [String: Any]) -> SessionTimelineEntry? {
        guard let text = extractVisibleText(from: payload),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return SessionTimelineEntry(
            role: .user,
            content: text,
            blocks: [.text(text)]
        )
    }

    private static func resolvedRole(from payload: [String: Any], fallbackType: String?) -> Message.MessageRole {
        if let parsedRole = explicitRole(from: payload) {
            return parsedRole
        }

        if let fallbackType {
            return role(forType: fallbackType)
        }

        return .system
    }

    private static func timelineContent(from blocks: [SessionContentBlock]) -> String {
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

    private static func extractVisibleText(from payload: [String: Any]) -> String? {
        if let text = sanitizedText(payload["text"] as? String) { return text }

        if let message = sanitizedText(payload["message"] as? String) { return message }

        if let message = payload["message"] as? [String: Any] {
            if let text = sanitizedText(message["text"] as? String) { return text }

            if let messageContent = message["content"] {
                let fragments = textFragments(from: messageContent)
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

    // MARK: - Private Helpers

    private static func messageType(from payload: [String: Any]) -> String? {
        guard let type = payload["type"] as? String else { return nil }
        return type.lowercased()
    }

    private static func explicitRole(from payload: [String: Any]) -> Message.MessageRole? {
        if let rawRole = payload["role"] as? String,
           let parsedRole = Message.MessageRole(rawValue: rawRole.lowercased()) {
            return parsedRole
        }

        if let message = payload["message"] as? [String: Any],
           let rawRole = message["role"] as? String,
           let parsedRole = Message.MessageRole(rawValue: rawRole.lowercased()) {
            return parsedRole
        }

        return nil
    }

    private static func role(forType type: String) -> Message.MessageRole {
        switch type.lowercased() {
        case "user", "user_prompt_command", "user_confirmation_command", "mcq_response_command":
            return .user
        case "assistant", "result", "output_chunk", "streaming_thinking", "streaming_generating", "terminal_output":
            return .assistant
        default:
            return .system
        }
    }

    private static func sanitizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func visibleToolResultTextFragments(from block: [String: Any]) -> [String] {
        if let content = sanitizedText(block["content"] as? String),
           !looksLikeProtocolArtifact(content) {
            return [content]
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
        guard text.hasPrefix("{"), text.hasSuffix("}"),
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = (json["type"] as? String)?.lowercased() else {
            return false
        }

        return protocolTypes.contains(type)
    }

    private static func appendOrUpdateStandaloneTool(_ toolUse: SessionToolUse, to blocks: inout [SessionContentBlock]) {
        let key = toolDedupKey(for: toolUse)
        if let existingIndex = blocks.firstIndex(where: { block in
            guard case .toolUse(let existingTool) = block else { return false }
            return toolDedupKey(for: existingTool) == key
        }) {
            blocks[existingIndex] = .toolUse(toolUse)
        } else {
            blocks.append(.toolUse(toolUse))
        }
    }

    private static func mergedSubAgentActivity(
        existing: SessionSubAgentActivity,
        incoming: SessionSubAgentActivity
    ) -> SessionSubAgentActivity {
        SessionSubAgentActivity(
            id: existing.id,
            parentToolUseId: existing.parentToolUseId,
            subagentType: mergedSubagentType(existing: existing.subagentType, incoming: incoming.subagentType),
            description: mergedDescription(existing: existing.description, incoming: incoming.description),
            tools: mergeTools(existing: existing.tools, incoming: incoming.tools)
        )
    }

    private static func mergedDescription(existing: String, incoming: String) -> String {
        guard sanitizedText(incoming) != nil else { return existing }
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

    private static func jsonPayload(from plaintext: String) -> [String: Any]? {
        guard let data = plaintext.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let payload = jsonObject as? [String: Any] else {
            return nil
        }
        return payload
    }

    private static func textFragments(from value: Any) -> [String] {
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
}
