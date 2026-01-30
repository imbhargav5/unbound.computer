import Foundation

struct ConversationEvent: Identifiable, Codable, Sendable {
    let eventId: String
    let sessionId: UUID
    let type: ConversationEventType
    let createdAt: Date
    let payload: EventPayload

    // Redis stream metadata (hot path only)
    var streamId: String?

    var id: String { eventId }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case sessionId = "session_id"
        case type
        case createdAt = "created_at"
        case payload
        case streamId = "stream_id"
    }
}

enum ConversationEventType: String, Codable, Sendable {
    // Output events
    case outputChunk = "OUTPUT_CHUNK"
    case streamingThinking = "STREAMING_THINKING"
    case streamingGenerating = "STREAMING_GENERATING"
    case streamingWaiting = "STREAMING_WAITING"
    case streamingIdle = "STREAMING_IDLE"

    // Tool events
    case toolStarted = "TOOL_STARTED"
    case toolOutputChunk = "TOOL_OUTPUT_CHUNK"
    case toolCompleted = "TOOL_COMPLETED"
    case toolFailed = "TOOL_FAILED"
    case toolApprovalRequired = "TOOL_APPROVAL_REQUIRED"

    // Question events
    case questionAsked = "QUESTION_ASKED"
    case questionAnswered = "QUESTION_ANSWERED"

    // User input commands
    case userPromptCommand = "USER_PROMPT_COMMAND"
    case userConfirmationCommand = "USER_CONFIRMATION_COMMAND"
    case mcqResponseCommand = "MCQ_RESPONSE_COMMAND"

    // File events
    case fileCreated = "FILE_CREATED"
    case fileModified = "FILE_MODIFIED"
    case fileDeleted = "FILE_DELETED"
    case fileRenamed = "FILE_RENAMED"

    // Execution events
    case executionStarted = "EXECUTION_STARTED"
    case executionCompleted = "EXECUTION_COMPLETED"

    // Session state events
    case sessionStateChanged = "SESSION_STATE_CHANGED"
    case sessionError = "SESSION_ERROR"
    case sessionWarning = "SESSION_WARNING"
    case rateLimitWarning = "RATE_LIMIT_WARNING"

    // Session control commands
    case sessionPauseCommand = "SESSION_PAUSE_COMMAND"
    case sessionResumeCommand = "SESSION_RESUME_COMMAND"
    case sessionStopCommand = "SESSION_STOP_COMMAND"
    case sessionCancelCommand = "SESSION_CANCEL_COMMAND"

    // Health events
    case sessionHeartbeat = "SESSION_HEARTBEAT"
    case connectionQualityUpdate = "CONNECTION_QUALITY_UPDATE"

    // TODO events
    case todoListUpdated = "TODO_LIST_UPDATED"
    case todoItemUpdated = "TODO_ITEM_UPDATED"

    var category: EventCategory {
        switch self {
        case .outputChunk, .streamingThinking, .streamingGenerating, .streamingWaiting, .streamingIdle:
            return .output
        case .toolStarted, .toolOutputChunk, .toolCompleted, .toolFailed, .toolApprovalRequired:
            return .tool
        case .questionAsked, .questionAnswered:
            return .question
        case .userPromptCommand, .userConfirmationCommand, .mcqResponseCommand:
            return .userInput
        case .fileCreated, .fileModified, .fileDeleted, .fileRenamed:
            return .file
        case .executionStarted, .executionCompleted:
            return .execution
        case .sessionStateChanged, .sessionError, .sessionWarning, .rateLimitWarning:
            return .sessionState
        case .sessionPauseCommand, .sessionResumeCommand, .sessionStopCommand, .sessionCancelCommand:
            return .sessionControl
        case .sessionHeartbeat, .connectionQualityUpdate:
            return .health
        case .todoListUpdated, .todoItemUpdated:
            return .todo
        }
    }

    var icon: String {
        switch category {
        case .output: return "text.bubble"
        case .tool: return "hammer"
        case .question: return "questionmark.circle"
        case .userInput: return "keyboard"
        case .file: return "doc"
        case .execution: return "play.circle"
        case .sessionState: return "info.circle"
        case .sessionControl: return "hand.raised"
        case .health: return "heart"
        case .todo: return "checklist"
        }
    }
}

enum EventCategory: String, Sendable {
    case output
    case tool
    case question
    case userInput
    case file
    case execution
    case sessionState
    case sessionControl
    case health
    case todo
}

// Dynamic payload based on event type
enum EventPayload: Codable, Sendable {
    case text(String)
    case json([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self = .json(dict)
        } else {
            self = .json([:])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .text(let string):
            try container.encode(string)
        case .json(let dict):
            try container.encode(dict)
        }
    }
}

// Helper to decode arbitrary JSON
struct AnyCodable: Codable, Sendable {
    let value: SendableValue

    init(_ value: Any) {
        // Since we can't check for Sendable at runtime, store based on type
        switch value {
        case let string as String:
            self.value = .string(string)
        case let int as Int:
            self.value = .int(int)
        case let double as Double:
            self.value = .double(double)
        case let bool as Bool:
            self.value = .bool(bool)
        case let array as [AnyCodable]:
            self.value = .array(array)
        case let dict as [String: AnyCodable]:
            self.value = .dictionary(dict)
        default:
            self.value = .unknown
        }
    }

    enum SendableValue: Sendable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case array([AnyCodable])
        case dictionary([String: AnyCodable])
        case unknown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            value = .int(int)
        } else if let double = try? container.decode(Double.self) {
            value = .double(double)
        } else if let string = try? container.decode(String.self) {
            value = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            value = .array(array)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = .dictionary(dict)
        } else {
            value = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .dictionary(let dict):
            try container.encode(dict)
        case .unknown:
            try container.encodeNil()
        }
    }
}
