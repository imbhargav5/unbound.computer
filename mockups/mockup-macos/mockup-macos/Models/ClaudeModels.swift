//
//  ClaudeModels.swift
//  mockup-macos
//
//  Models for Claude CLI output parsing and structured content
//

import Foundation

// MARK: - Message Content

enum MessageContent: Identifiable, Hashable {
    case text(TextContent)
    case codeBlock(CodeBlock)
    case askUserQuestion(AskUserQuestion)
    case todoList(TodoList)
    case fileChange(FileChange)
    case toolUse(ToolUse)
    case subAgentActivity(SubAgentActivity)
    case error(ErrorContent)

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
        }
    }
}

// MARK: - Text Content

struct TextContent: Identifiable, Hashable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

// MARK: - Code Block

struct CodeBlock: Identifiable, Hashable {
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

struct AskUserQuestion: Identifiable, Hashable {
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

struct QuestionOption: Identifiable, Hashable {
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

struct TodoList: Identifiable, Hashable {
    let id: UUID
    var items: [TodoItem]

    init(id: UUID = UUID(), items: [TodoItem] = []) {
        self.id = id
        self.items = items
    }
}

struct TodoItem: Identifiable, Hashable {
    let id: UUID
    let content: String
    var status: TodoStatus

    init(id: UUID = UUID(), content: String, status: TodoStatus = .pending) {
        self.id = id
        self.content = content
        self.status = status
    }
}

enum TodoStatus: String, Hashable {
    case pending
    case inProgress = "in_progress"
    case completed
}

// MARK: - File Change

struct FileChange: Identifiable, Hashable {
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

enum FileChangeType: String, Hashable {
    case created
    case modified
    case deleted
    case renamed
}

// MARK: - Tool Use

struct ToolUse: Identifiable, Hashable {
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

enum ToolStatus: String, Hashable {
    case running
    case completed
    case failed
}

// MARK: - Sub-Agent Activity

/// Represents a grouped sub-agent (Task tool) activity with its child tools
struct SubAgentActivity: Identifiable, Hashable {
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

struct ErrorContent: Identifiable, Hashable {
    let id: UUID
    let message: String
    let details: String?

    init(id: UUID = UUID(), message: String, details: String? = nil) {
        self.id = id
        self.message = message
        self.details = details
    }
}
