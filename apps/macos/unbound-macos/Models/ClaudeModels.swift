//
//  ClaudeModels.swift
//  unbound-macos
//
//  Models for Claude CLI output parsing and structured content
//

import Foundation

// MARK: - Message Content

enum MessageContent: Identifiable, Hashable, Codable {
    case text(TextContent)
    case codeBlock(CodeBlock)
    case askUserQuestion(AskUserQuestion)
    case todoList(TodoList)
    case fileChange(FileChange)
    case toolUse(ToolUse)
    case subAgentActivity(SubAgentActivity)
    case error(ErrorContent)
    case eventPayload(EventPayload)  // Generic event payload for relay transmission

    var id: UUID {
        switch self {
        case .text(let content): return content.id
        case .codeBlock(let content): return content.id
        case .askUserQuestion(let content): return content.id
        case .todoList(let content): return content.id
        case .fileChange(let content): return content.id
        case .toolUse(let content): return content.id
        case .subAgentActivity(let content): return content.id
        case .error(let content): return content.id
        case .eventPayload(let content): return content.id
        }
    }
}

// MARK: - Text Content

struct TextContent: Identifiable, Hashable, Codable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

// MARK: - Code Block

struct CodeBlock: Identifiable, Hashable, Codable {
    let id: UUID
    let language: String
    let code: String
    let filename: String?

    init(id: UUID = UUID(), language: String = "", code: String, filename: String? = nil) {
        self.id = id
        self.language = language
        self.code = code
        self.filename = filename
    }
}

// MARK: - Ask User Question

struct AskUserQuestion: Identifiable, Hashable, Codable {
    let id: UUID
    let question: String
    let header: String?
    let options: [QuestionOption]
    let allowsMultiSelect: Bool
    let allowsTextInput: Bool
    var selectedOptions: Set<String>
    var textResponse: String?

    init(
        id: UUID = UUID(),
        question: String,
        header: String? = nil,
        options: [QuestionOption] = [],
        allowsMultiSelect: Bool = false,
        allowsTextInput: Bool = true,
        selectedOptions: Set<String> = [],
        textResponse: String? = nil
    ) {
        self.id = id
        self.question = question
        self.header = header
        self.options = options
        self.allowsMultiSelect = allowsMultiSelect
        self.allowsTextInput = allowsTextInput
        self.selectedOptions = selectedOptions
        self.textResponse = textResponse
    }
}

struct QuestionOption: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let description: String?

    init(id: String = UUID().uuidString, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

// MARK: - Todo List

struct TodoList: Identifiable, Hashable, Codable {
    let id: UUID
    var items: [TodoItem]
    let sourceToolUseId: String?
    let parentToolUseId: String?

    init(
        id: UUID = UUID(),
        items: [TodoItem] = [],
        sourceToolUseId: String? = nil,
        parentToolUseId: String? = nil
    ) {
        self.id = id
        self.items = items
        self.sourceToolUseId = sourceToolUseId
        self.parentToolUseId = parentToolUseId
    }
}

struct TodoItem: Identifiable, Hashable, Codable {
    let id: UUID
    let content: String
    var status: TodoStatus

    init(id: UUID = UUID(), content: String, status: TodoStatus = .pending) {
        self.id = id
        self.content = content
        self.status = status
    }
}

enum TodoStatus: String, Hashable, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
}

// MARK: - File Change

struct FileChange: Identifiable, Hashable, Codable {
    let id: UUID
    let filePath: String
    let changeType: FileChangeType
    let diff: String?
    let linesAdded: Int
    let linesRemoved: Int

    init(
        id: UUID = UUID(),
        filePath: String,
        changeType: FileChangeType,
        diff: String? = nil,
        linesAdded: Int = 0,
        linesRemoved: Int = 0
    ) {
        self.id = id
        self.filePath = filePath
        self.changeType = changeType
        self.diff = diff
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}

enum FileChangeType: String, Hashable, Codable {
    case created
    case modified
    case deleted
    case renamed
}

// MARK: - Tool Use

struct ToolUse: Identifiable, Hashable, Codable {
    let id: UUID
    /// The tool_use_id from Claude CLI, used to match with tool_result
    let toolUseId: String?
    /// The parent tool_use_id for sub-agent child tools (if any)
    let parentToolUseId: String?
    let toolName: String
    let input: String?
    var output: String?
    var status: ToolStatus

    init(
        id: UUID = UUID(),
        toolUseId: String? = nil,
        parentToolUseId: String? = nil,
        toolName: String,
        input: String? = nil,
        output: String? = nil,
        status: ToolStatus = .running
    ) {
        self.id = id
        self.toolUseId = toolUseId
        self.parentToolUseId = parentToolUseId
        self.toolName = toolName
        self.input = input
        self.output = output
        self.status = status
    }
}

enum ToolStatus: String, Hashable, Codable {
    case running
    case completed
    case failed
}

// MARK: - Sub-Agent Activity

/// Represents a grouped sub-agent (Task tool) activity with its child tools
struct SubAgentActivity: Identifiable, Hashable, Codable {
    let id: UUID
    /// The Task tool's tool_use_id, used to match completion
    let parentToolUseId: String
    /// The type of sub-agent: "Explore", "Plan", "general-purpose", etc.
    let subagentType: String
    /// Task description/prompt
    let description: String
    /// Child tools executed by the sub-agent
    var tools: [ToolUse]
    /// Status of the sub-agent activity
    var status: ToolStatus
    /// Final result text from the sub-agent
    var result: String?

    init(
        id: UUID = UUID(),
        parentToolUseId: String,
        subagentType: String,
        description: String,
        tools: [ToolUse] = [],
        status: ToolStatus = .running,
        result: String? = nil
    ) {
        self.id = id
        self.parentToolUseId = parentToolUseId
        self.subagentType = subagentType
        self.description = description
        self.tools = tools
        self.status = status
        self.result = result
    }
}

// MARK: - Error Content

struct ErrorContent: Identifiable, Hashable, Codable {
    let id: UUID
    let message: String
    let details: String?

    init(id: UUID = UUID(), message: String, details: String? = nil) {
        self.id = id
        self.message = message
        self.details = details
    }
}

// MARK: - Event Payload

/// Generic event payload for relay transmission
/// Used to store arbitrary event data as encrypted message rows
struct EventPayload: Identifiable, Hashable, Codable {
    let id: UUID
    let eventType: String
    let data: [String: EventPayloadValue]

    init(id: UUID = UUID(), eventType: String, data: [String: Any]) {
        self.id = id
        self.eventType = eventType
        self.data = data.mapValues { EventPayloadValue($0) }
    }

    /// Convert data back to dictionary of Any values
    func toDict() -> [String: Any] {
        data.mapValues { $0.value }
    }
}

/// Type-erased wrapper for event payload values
struct EventPayloadValue: Hashable, Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([EventPayloadValue].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: EventPayloadValue].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON type in EventPayloadValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { EventPayloadValue($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { EventPayloadValue($0) })
        default:
            // Try to encode as string representation
            try container.encode(String(describing: value))
        }
    }

    static func == (lhs: EventPayloadValue, rhs: EventPayloadValue) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}

// MARK: - Claude Output

enum ClaudeOutput {
    case text(String)
    case structuredBlock(MessageContent)
    case prompt(AskUserQuestion)
    case sessionStarted(String)  // session_id
    case toolResult(toolUseId: String, output: String)  // tool_use_id and result content
    case complete
    case error(String)
}

// MARK: - Claude Stream Item

/// Wrapper that includes both the raw NDJSON line and parsed output.
/// Used to store raw events to database immediately while also updating UI.
struct ClaudeStreamItem {
    /// The raw NDJSON line exactly as received from Claude CLI
    let rawJson: String
    /// The parsed output for UI consumption (nil if line was filtered/unparseable)
    let output: ClaudeOutput?
}

// MARK: - Claude Process State

struct ClaudeProcessState {
    var isRunning: Bool = false
    var processId: UUID?
    var outputBuffer: String = ""
}

// MARK: - Claude JSON Message Types (for stream-json output)

/// Root message envelope from Claude CLI stream-json
struct ClaudeJSONMessage: Decodable {
    let type: String
    let subtype: String?
    let sessionId: String?
    let message: ClaudeMessageBody?
    let toolUseId: String?
    let name: String?
    let input: AnyCodable?
    let content: String?
    /// Result can be either a ClaudeResultBody object or a plain string (from task agents)
    let result: ClaudeResultBody?
    let resultString: String?
    let costUsd: Double?
    let durationMs: Int?
    let durationApiMs: Int?
    let isError: Bool?
    let numTurns: Int?

    enum CodingKeys: String, CodingKey {
        case type, subtype, message, content, name, input
        case sessionId = "session_id"
        case toolUseId = "tool_use_id"
        case costUsd = "cost_usd"
        case durationMs = "duration_ms"
        case durationApiMs = "duration_api_ms"
        case isError = "is_error"
        case numTurns = "num_turns"
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        message = try container.decodeIfPresent(ClaudeMessageBody.self, forKey: .message)
        toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        input = try container.decodeIfPresent(AnyCodable.self, forKey: .input)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        durationApiMs = try container.decodeIfPresent(Int.self, forKey: .durationApiMs)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
        numTurns = try container.decodeIfPresent(Int.self, forKey: .numTurns)

        // Handle result which can be either a string or an object
        if let stringResult = try? container.decodeIfPresent(String.self, forKey: .result) {
            resultString = stringResult
            result = nil
        } else {
            result = try container.decodeIfPresent(ClaudeResultBody.self, forKey: .result)
            resultString = nil
        }
    }
}

/// Message body containing role and content
struct ClaudeMessageBody: Decodable {
    let role: String?
    let content: [ClaudeContentBlock]?

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)

        // Decode content blocks individually to be resilient to malformed blocks
        if var contentContainer = try? container.nestedUnkeyedContainer(forKey: .content) {
            var blocks: [ClaudeContentBlock] = []
            while !contentContainer.isAtEnd {
                // Try to decode each block, skip if it fails
                if let block = try? contentContainer.decode(ClaudeContentBlock.self) {
                    blocks.append(block)
                } else {
                    // Skip malformed block by decoding as AnyCodable
                    _ = try? contentContainer.decode(AnyCodable.self)
                }
            }
            content = blocks.isEmpty ? nil : blocks
        } else {
            content = nil
        }
    }
}

/// Content block within a message
struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
    /// The ID for this block - tool_use uses "id", tool_result uses "tool_use_id"
    let toolUseId: String?
    let name: String?
    let input: AnyCodable?
    /// Content can be a string or an array of content blocks (for tool_result)
    let content: String?

    enum CodingKeys: String, CodingKey {
        case type, text, name, input, content
        case toolUseId = "tool_use_id"
        case id  // tool_use blocks use "id" instead of "tool_use_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        // tool_use blocks use "id", tool_result blocks use "tool_use_id"
        toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
            ?? (try container.decodeIfPresent(String.self, forKey: .id))
        name = try container.decodeIfPresent(String.self, forKey: .name)
        input = try container.decodeIfPresent(AnyCodable.self, forKey: .input)

        // Handle content which can be String, Array of content blocks, or other types
        if let stringContent = try? container.decodeIfPresent(String.self, forKey: .content) {
            content = stringContent
        } else if let arrayContent = try? container.decodeIfPresent([ToolResultContentBlock].self, forKey: .content) {
            // Extract text from array of content blocks
            content = arrayContent.compactMap { $0.text }.joined(separator: "\n")
        } else if container.contains(.content) {
            // Content exists but is some other type (object, null, etc.) - try to serialize it
            if let anyContent = try? container.decodeIfPresent(AnyCodable.self, forKey: .content) {
                content = anyContent.jsonString
            } else {
                content = nil
            }
        } else {
            content = nil
        }
    }
}

/// Content block within a tool_result (simplified structure)
/// Handles text blocks and gracefully ignores other types (images, etc.)
private struct ToolResultContentBlock: Decodable {
    let type: String
    let text: String?

    enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Use try? to be resilient - if type is missing, default to "unknown"
        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        text = try? container.decodeIfPresent(String.self, forKey: .text)
    }
}

/// Result body for completion messages
struct ClaudeResultBody: Decodable {
    let role: String?
    let content: [ClaudeContentBlock]?

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)

        // Decode content blocks individually to be resilient to malformed blocks
        if var contentContainer = try? container.nestedUnkeyedContainer(forKey: .content) {
            var blocks: [ClaudeContentBlock] = []
            while !contentContainer.isAtEnd {
                if let block = try? contentContainer.decode(ClaudeContentBlock.self) {
                    blocks.append(block)
                } else {
                    _ = try? contentContainer.decode(AnyCodable.self)
                }
            }
            content = blocks.isEmpty ? nil : blocks
        } else {
            content = nil
        }
    }
}

/// Type-erased Codable for handling dynamic JSON
struct AnyCodable: Decodable, Hashable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }

    /// Convert to pretty-printed JSON string for display
    var jsonString: String {
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}
