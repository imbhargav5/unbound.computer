//
//  ChatModels.swift
//  unbound-macos
//
//  Chat message models used in conversations (Sessions).
//  Note: ChatTab was removed - Session now represents conversations directly.
//

import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: MessageRole
    var content: [MessageContent]
    let timestamp: Date
    var isStreaming: Bool
    var sequenceNumber: Int

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: [MessageContent] = [],
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        sequenceNumber: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.sequenceNumber = sequenceNumber
    }

    /// Convenience initializer for simple text message
    init(id: UUID = UUID(), role: MessageRole, text: String, timestamp: Date = Date(), sequenceNumber: Int = 0) {
        self.id = id
        self.role = role
        self.content = [.text(TextContent(text: text))]
        self.timestamp = timestamp
        self.isStreaming = false
        self.sequenceNumber = sequenceNumber
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

// MARK: - Think Mode

/// Extended thinking modes for Claude - controls depth of reasoning
enum ThinkMode: String, CaseIterable, Identifiable, Hashable {
    case none = "none"
    case think = "think"           // Standard extended thinking
    case ultrathink = "ultrathink" // Maximum depth extended thinking

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: return "Normal"
        case .think: return "Think"
        case .ultrathink: return "Ultra Think"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "bolt"
        case .think: return "brain"
        case .ultrathink: return "brain.head.profile"
        }
    }

    var description: String {
        switch self {
        case .none: return "Fast responses"
        case .think: return "Extended reasoning"
        case .ultrathink: return "Maximum depth reasoning"
        }
    }
}

// MARK: - AI Model

struct AIModel: Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String
    /// The model identifier to pass to Claude CLI --model flag, nil means use default
    let modelIdentifier: String?
    /// Whether this model supports extended thinking
    let supportsThinking: Bool

    init(id: String, name: String, iconName: String, modelIdentifier: String?, supportsThinking: Bool = false) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.modelIdentifier = modelIdentifier
        self.supportsThinking = supportsThinking
    }

    /// Default model - uses Claude's default (currently Sonnet)
    static let defaultModel = AIModel(
        id: "default",
        name: "Default (Recommended)",
        iconName: "star.fill",
        modelIdentifier: nil,
        supportsThinking: true
    )

    /// Claude Opus 4.5 - highest capability with extended thinking
    static let opus = AIModel(
        id: "opus-4.5",
        name: "Opus 4.5",
        iconName: "sparkles",
        modelIdentifier: "claude-opus-4-5-20251101",
        supportsThinking: true
    )

    /// Claude Sonnet 4.5 - balanced performance with extended thinking
    static let sonnet = AIModel(
        id: "sonnet-4.5",
        name: "Sonnet 4.5",
        iconName: "sparkle",
        modelIdentifier: "claude-sonnet-4-5-20250929",
        supportsThinking: true
    )

    /// Claude Haiku 4.5 - fastest, lightweight (no extended thinking)
    static let haiku = AIModel(
        id: "haiku-4.5",
        name: "Haiku 4.5",
        iconName: "leaf",
        modelIdentifier: "claude-haiku-4-5-20251001",
        supportsThinking: false
    )

    static let allModels: [AIModel] = [.defaultModel, .opus, .sonnet, .haiku]
}
