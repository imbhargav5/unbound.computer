import Foundation

public enum ClaudeConversationRole: String, Codable, Sendable {
    case assistant
    case user
    case system
    case result
    case unknown
}

public enum ClaudeConversationBlock: Equatable, Sendable {
    case text(String)
    case toolCall(ClaudeToolCallBlock)
    case subAgent(ClaudeSubAgentBlock)
    case compactBoundary
    case result(ClaudeResultBlock)
    case error(String)
    case unknown(String)
}

public struct ClaudeToolCallBlock: Equatable, Sendable {
    public let toolUseId: String?
    public let parentToolUseId: String?
    public let name: String
    public let input: String?
    public let status: ClaudeToolCallStatus
    public let resultText: String?

    public init(
        toolUseId: String?,
        parentToolUseId: String?,
        name: String,
        input: String?,
        status: ClaudeToolCallStatus,
        resultText: String?
    ) {
        self.toolUseId = toolUseId
        self.parentToolUseId = parentToolUseId
        self.name = name
        self.input = input
        self.status = status
        self.resultText = resultText
    }

    public func with(status: ClaudeToolCallStatus, resultText: String?) -> ClaudeToolCallBlock {
        ClaudeToolCallBlock(
            toolUseId: toolUseId,
            parentToolUseId: parentToolUseId,
            name: name,
            input: input,
            status: status,
            resultText: resultText ?? self.resultText
        )
    }
}

public enum ClaudeToolCallStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
}

public struct ClaudeSubAgentBlock: Equatable, Sendable {
    public let parentToolUseId: String
    public let subagentType: String
    public let description: String
    public let tools: [ClaudeToolCallBlock]
    public let status: ClaudeToolCallStatus
    public let result: String?

    public init(
        parentToolUseId: String,
        subagentType: String,
        description: String,
        tools: [ClaudeToolCallBlock],
        status: ClaudeToolCallStatus,
        result: String?
    ) {
        self.parentToolUseId = parentToolUseId
        self.subagentType = subagentType
        self.description = description
        self.tools = tools
        self.status = status
        self.result = result
    }

    public func with(tools: [ClaudeToolCallBlock], status: ClaudeToolCallStatus, result: String?) -> ClaudeSubAgentBlock {
        ClaudeSubAgentBlock(
            parentToolUseId: parentToolUseId,
            subagentType: subagentType,
            description: description,
            tools: tools,
            status: status,
            result: result ?? self.result
        )
    }
}

public struct ClaudeResultBlock: Equatable, Sendable {
    public let isError: Bool
    public let text: String?
    public let permissionDenials: [String]

    public init(isError: Bool, text: String?, permissionDenials: [String]) {
        self.isError = isError
        self.text = text
        self.permissionDenials = permissionDenials
    }
}

public struct ClaudeConversationTimelineEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: ClaudeConversationRole
    public let blocks: [ClaudeConversationBlock]
    public let createdAt: Date?
    public let sequence: Int?
    public let sourceType: String

    public init(
        id: String,
        role: ClaudeConversationRole,
        blocks: [ClaudeConversationBlock],
        createdAt: Date?,
        sequence: Int?,
        sourceType: String
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.createdAt = createdAt
        self.sequence = sequence
        self.sourceType = sourceType
    }
}
