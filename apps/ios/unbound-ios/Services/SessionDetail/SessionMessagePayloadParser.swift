//
//  SessionMessagePayloadParser.swift
//  unbound-ios
//
//  Shared parser for decrypted session message payloads.
//

import Foundation

enum SessionMessagePayloadParser {
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
            return jsonPayload(from: wrappedRawJSON)
        }
        return payload
    }

    private static func parseAssistantBlocks(_ payload: [String: Any]) -> [SessionContentBlock] {
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
            case "tool_use":
                if let name = block["name"] as? String {
                    let inputDict = block["input"] as? [String: Any]
                    let summary = toolSummary(name: name, input: inputDict)
                    blocks.append(.toolUse(SessionToolUse(
                        id: UUID(),
                        toolName: name,
                        summary: summary
                    )))
                }
            default:
                break
            }
        }

        return blocks
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
