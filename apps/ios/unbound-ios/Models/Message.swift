import Foundation
import SwiftUI

struct Message: Identifiable, Hashable {
    let id: UUID
    let content: String
    let role: MessageRole
    let timestamp: Date
    let codeBlocks: [CodeBlock]?
    let isStreaming: Bool
    var richContent: ChatContent?

    init(
        id: UUID = UUID(),
        content: String,
        role: MessageRole,
        timestamp: Date = Date(),
        codeBlocks: [CodeBlock]? = nil,
        isStreaming: Bool = false,
        richContent: ChatContent? = nil
    ) {
        self.id = id
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.codeBlocks = codeBlocks
        self.isStreaming = isStreaming
        self.richContent = richContent
    }

    enum MessageRole: String, Codable {
        case user
        case assistant
        case system

        var alignment: HorizontalAlignment {
            switch self {
            case .user:
                return .trailing
            case .assistant, .system:
                return .leading
            }
        }
    }

    struct CodeBlock: Identifiable, Hashable {
        let id: UUID
        let language: String
        let code: String
        let filename: String?
    }
}
