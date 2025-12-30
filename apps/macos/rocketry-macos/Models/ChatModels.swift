//
//  ChatModels.swift
//  rocketry-macos
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import Foundation

// MARK: - Chat Tab

struct ChatTab: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    /// Claude CLI session ID for resuming conversations
    var claudeSessionId: String?

    init(id: UUID = UUID(), title: String = "Untitled", messages: [ChatMessage] = [], createdAt: Date = Date(), claudeSessionId: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.claudeSessionId = claudeSessionId
    }

    /// Display title - uses first user message preview or default title
    var displayTitle: String {
        // Find first user message with text content
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let text = firstUserMessage.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                // Truncate to ~30 chars
                let truncated = String(text.prefix(30))
                return truncated.count < text.count ? truncated + "..." : truncated
            }
        }
        return title.isEmpty ? "New chat" : title
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: MessageRole
    var content: [MessageContent]
    let timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: [MessageContent] = [],
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    /// Convenience initializer for simple text message
    init(id: UUID = UUID(), role: MessageRole, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = [.text(TextContent(text: text))]
        self.timestamp = timestamp
        self.isStreaming = false
    }

    /// Get all text content concatenated
    var textContent: String {
        content.compactMap { item in
            if case .text(let textContent) = item {
                return textContent.text
            }
            return nil
        }.joined(separator: "\n")
    }
}

// MARK: - Message Role

enum MessageRole: String, Hashable, Codable {
    case user
    case assistant
    case system
}

// MARK: - AI Model

struct AIModel: Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String
    /// The model identifier to pass to Claude CLI --model flag, nil means use default
    let modelIdentifier: String?

    /// Default model - uses Claude's default (currently Sonnet)
    static let defaultModel = AIModel(
        id: "default",
        name: "Default (Recommended)",
        iconName: "star.fill",
        modelIdentifier: nil
    )

    /// Claude Opus 4.5 - highest capability
    static let opus = AIModel(
        id: "opus-4.5",
        name: "Opus 4.5",
        iconName: "sparkles",
        modelIdentifier: "claude-opus-4-5-20251101"
    )

    /// Claude Sonnet 4.5 - balanced performance
    static let sonnet = AIModel(
        id: "sonnet-4.5",
        name: "Sonnet 4.5",
        iconName: "sparkle",
        modelIdentifier: "claude-sonnet-4-5-20250929"
    )

    /// Claude Haiku 4.5 - fastest, lightweight
    static let haiku = AIModel(
        id: "haiku-4.5",
        name: "Haiku 4.5",
        iconName: "leaf",
        modelIdentifier: "claude-haiku-4-5-20251001"
    )

    static let allModels: [AIModel] = [.defaultModel, .opus, .sonnet, .haiku]
}
