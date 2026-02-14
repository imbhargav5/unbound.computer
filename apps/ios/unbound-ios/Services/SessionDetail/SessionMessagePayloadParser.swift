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
    static func timelineEntry(from plaintext: String) -> SessionTimelineEntry? {
        guard let payload = resolvedPayload(from: plaintext) else {
            let text = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SessionTimelineEntry(role: .user, content: text, blocks: [.text(text)])
        }

        return buildTimelineEntry(from: payload, plaintext: plaintext)
    }

    static func role(from plaintext: String) -> Message.MessageRole {
        guard let payload = jsonPayload(from: plaintext) else {
            return .system
        }

        if let rawRole = payload["role"] as? String,
           let parsedRole = Message.MessageRole(rawValue: rawRole.lowercased()) {
            return parsedRole
        }

        if let wrappedRawJSON = payload["raw_json"] as? String {
            return role(from: wrappedRawJSON)
        }

        if let type = payload["type"] as? String {
            switch type.lowercased() {
            case "user", "user_prompt_command", "user_confirmation_command", "mcq_response_command":
                return .user
            case "assistant", "result", "output_chunk", "streaming_thinking", "streaming_generating":
                return .assistant
            default:
                return .system
            }
        }

        return .system
    }

    static func displayText(from plaintext: String) -> String {
        guard let payload = jsonPayload(from: plaintext) else {
            return plaintext
        }

        if let wrappedRawJSON = payload["raw_json"] as? String {
            return displayText(from: wrappedRawJSON)
        }

        if let text = payload["text"] as? String, !text.isEmpty {
            return text
        }

        if let message = payload["message"] as? String, !message.isEmpty {
            return message
        }

        if let content = payload["content"] as? String, !content.isEmpty {
            return content
        }

        if let content = payload["content"] {
            let fragments = textFragments(from: content)
            if !fragments.isEmpty {
                return fragments.joined(separator: "\n")
            }
        }

        if let type = payload["type"] as? String,
           type.lowercased() == "terminal_output",
           let stream = payload["stream"] as? String,
           let content = payload["content"] as? String {
            return "[\(stream)] \(content)"
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
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

        guard let type = payload["type"] as? String else {
            return fallbackBlocks(from: plaintext)
        }

        switch type.lowercased() {
        case "assistant":
            return parseAssistantBlocks(payload)
        case "user", "user_prompt_command":
            return parseUserBlocks(payload)
        case "result":
            return parseResultBlocks(payload)
        default:
            return fallbackBlocks(from: plaintext)
        }
    }

    private static func resolvedPayload(from plaintext: String) -> [String: Any]? {
        guard let payload = jsonPayload(from: plaintext) else { return nil }
        if let wrappedRawJSON = payload["raw_json"] as? String {
            return jsonPayload(from: wrappedRawJSON) ?? payload
        }
        return payload
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
        var pendingToolOrder: [SessionToolUse] = []
        let messageParent = payload["parent_tool_use_id"] as? String

        for block in contentBlocks {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                        activity.tools.append(contentsOf: pendingTools)
                    }

                    blocks.append(.subAgentActivity(activity))
                    subAgentIndexByParent[taskId] = blocks.count - 1
                    continue
                }

                if let parentId = parentToolUseId {
                    if let index = subAgentIndexByParent[parentId],
                       case .subAgentActivity(var activity) = blocks[index] {
                        activity.tools.append(toolUse)
                        blocks[index] = .subAgentActivity(activity)
                    } else {
                        pendingToolsByParent[parentId, default: []].append(toolUse)
                        pendingToolOrder.append(toolUse)
                    }
                } else {
                    blocks.append(.toolUse(toolUse))
                }

            default:
                break
            }
        }

        if !pendingToolOrder.isEmpty {
            for toolUse in pendingToolOrder {
                guard let parentId = toolUse.parentToolUseId,
                      pendingToolsByParent[parentId] != nil else {
                    continue
                }
                blocks.append(.toolUse(toolUse))
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
        if let message = payload["message"] as? String,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                if let text = block["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(text))
                }
            case "tool_result":
                if let content = block["content"] as? String,
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(content))
                } else if let contentArray = block["content"] as? [[String: Any]] {
                    for item in contentArray {
                        if let text = item["text"] as? String,
                           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            blocks.append(.text(text))
                        }
                    }
                }
            default:
                break
            }
        }

        return blocks
    }

    private static func parseResultBlocks(_ payload: [String: Any]) -> [SessionContentBlock] {
        let isError = payload["is_error"] as? Bool ?? false
        if let result = payload["result"] as? String,
           !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return isError ? [.error(result)] : [.text(result)]
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
        let type = (payload["type"] as? String)?.lowercased()

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
                    if let text = block["text"] as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        userTextBlocks.append(.text(text))
                    }
                case "tool_result", "tool_use":
                    // Tool result summaries are protocol artifacts; hide them from timeline UI.
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
        if let rawRole = payload["role"] as? String,
           let parsedRole = Message.MessageRole(rawValue: rawRole.lowercased()) {
            return parsedRole
        }

        if let message = payload["message"] as? [String: Any],
           let rawRole = message["role"] as? String,
           let parsedRole = Message.MessageRole(rawValue: rawRole.lowercased()) {
            return parsedRole
        }

        if let fallbackType {
            switch fallbackType.lowercased() {
            case "user", "user_prompt_command", "user_confirmation_command", "mcq_response_command":
                return .user
            case "assistant", "terminal_output":
                return .assistant
            default:
                return .system
            }
        }

        return .user
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
        if let text = payload["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let message = payload["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let message = payload["message"] as? [String: Any] {
            if let text = message["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let messageContent = message["content"] {
                let fragments = textFragments(from: messageContent)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !fragments.isEmpty {
                    return fragments.joined(separator: "\n")
                }
            }
        }

        if let content = payload["content"] as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

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
