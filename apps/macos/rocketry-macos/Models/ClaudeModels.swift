//
//  ClaudeModels.swift
//  rocketry-macos
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
    case error(ErrorContent)

    var id: UUID {
        switch self {
        case .text(let content): return content.id
        case .codeBlock(let content): return content.id
        case .askUserQuestion(let content): return content.id
        case .todoList(let content): return content.id
        case .fileChange(let content): return content.id
        case .toolUse(let content): return content.id
        case .error(let content): return content.id
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

    init(id: UUID = UUID(), items: [TodoItem] = []) {
        self.id = id
        self.items = items
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
    let toolName: String
    let input: String?
    var output: String?
    var status: ToolStatus

    init(
        id: UUID = UUID(),
        toolUseId: String? = nil,
        toolName: String,
        input: String? = nil,
        output: String? = nil,
        status: ToolStatus = .running
    ) {
        self.id = id
        self.toolUseId = toolUseId
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
    let result: ClaudeResultBody?
    let costUsd: Double?
    let durationMs: Int?
    let durationApiMs: Int?
    let isError: Bool?
    let numTurns: Int?

    enum CodingKeys: String, CodingKey {
        case type, subtype, message, content, result, name, input
        case sessionId = "session_id"
        case toolUseId = "tool_use_id"
        case costUsd = "cost_usd"
        case durationMs = "duration_ms"
        case durationApiMs = "duration_api_ms"
        case isError = "is_error"
        case numTurns = "num_turns"
    }
}

/// Message body containing role and content
struct ClaudeMessageBody: Decodable {
    let role: String?
    let content: [ClaudeContentBlock]?
}

/// Content block within a message
struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
    let toolUseId: String?
    let name: String?
    let input: AnyCodable?
    let content: String?

    enum CodingKeys: String, CodingKey {
        case type, text, name, input, content
        case toolUseId = "tool_use_id"
    }
}

/// Result body for completion messages
struct ClaudeResultBody: Decodable {
    let role: String?
    let content: [ClaudeContentBlock]?
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
