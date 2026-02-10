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
