// This file was generated from Zod schemas, do not modify it directly.
// Run `/swift-codegen-generator` to regenerate.

import Foundation

// MARK: - Enums

public enum Opcode: String, Codable, Sendable {
    case event = "EVENT"
    case ack = "ACK"
}

public enum Plane: String, Codable, Sendable {
    case handshake = "HANDSHAKE"
    case session = "SESSION"
}

public enum SessionEventType: String, Codable, Sendable {
    case remoteCommand = "REMOTE_COMMAND"
    case executorUpdate = "EXECUTOR_UPDATE"
}

public enum HandshakeEventType: String, Codable, Sendable {
    case pairRequest = "PAIR_REQUEST"
    case pairAccepted = "PAIR_ACCEPTED"
    case sessionCreated = "SESSION_CREATED"
}

public enum SessionEventTypeValue: String, Codable, Sendable {
    // Session Control Commands
    case sessionPauseCommand = "SESSION_PAUSE_COMMAND"
    case sessionResumeCommand = "SESSION_RESUME_COMMAND"
    case sessionStopCommand = "SESSION_STOP_COMMAND"
    case sessionCancelCommand = "SESSION_CANCEL_COMMAND"
    // User Input Commands
    case userPromptCommand = "USER_PROMPT_COMMAND"
    case userConfirmationCommand = "USER_CONFIRMATION_COMMAND"
    case mcqResponseCommand = "MCQ_RESPONSE_COMMAND"
    case toolApprovalCommand = "TOOL_APPROVAL_COMMAND"
    // Worktree/Conflicts Commands
    case worktreeCreateCommand = "WORKTREE_CREATE_COMMAND"
    case conflictsFixCommand = "CONFLICTS_FIX_COMMAND"
    // Execution Updates
    case executionStarted = "EXECUTION_STARTED"
    case outputChunk = "OUTPUT_CHUNK"
    case executionCompleted = "EXECUTION_COMPLETED"
    case worktreeAdded = "WORKTREE_ADDED"
    case repositoryAdded = "REPOSITORY_ADDED"
    case repositoryRemoved = "REPOSITORY_REMOVED"
    case conflictsFixed = "CONFLICTS_FIXED"
    case conflictsFixFailed = "CONFLICTS_FIX_FAILED"
    case gitPushCompleted = "GIT_PUSH_COMPLETED"
    case gitPushFailed = "GIT_PUSH_FAILED"
    case conflictsFound = "CONFLICTS_FOUND"
    // Tool Execution Updates
    case toolStarted = "TOOL_STARTED"
    case toolOutputChunk = "TOOL_OUTPUT_CHUNK"
    case toolCompleted = "TOOL_COMPLETED"
    case toolFailed = "TOOL_FAILED"
    case toolApprovalRequired = "TOOL_APPROVAL_REQUIRED"
    // Streaming State Updates
    case streamingThinking = "STREAMING_THINKING"
    case streamingGenerating = "STREAMING_GENERATING"
    case streamingWaiting = "STREAMING_WAITING"
    case streamingIdle = "STREAMING_IDLE"
    // File Change Updates
    case fileCreated = "FILE_CREATED"
    case fileModified = "FILE_MODIFIED"
    case fileDeleted = "FILE_DELETED"
    case fileRenamed = "FILE_RENAMED"
    // Session Health Updates
    case sessionHeartbeat = "SESSION_HEARTBEAT"
    case sessionStateChanged = "SESSION_STATE_CHANGED"
    case connectionQualityUpdate = "CONNECTION_QUALITY_UPDATE"
    // Error/Warning Updates
    case sessionError = "SESSION_ERROR"
    case sessionWarning = "SESSION_WARNING"
    case rateLimitWarning = "RATE_LIMIT_WARNING"
    // Todo Updates
    case todoListUpdated = "TODO_LIST_UPDATED"
    case todoItemUpdated = "TODO_ITEM_UPDATED"
    // Question Events
    case questionAsked = "QUESTION_ASKED"
    case questionAnswered = "QUESTION_ANSWERED"
}

public enum AttachmentType: String, Codable, Sendable {
    case image = "image"
    case file = "file"
    case url = "url"
}

public enum SessionState: String, Codable, Sendable {
    case initializing = "initializing"
    case running = "running"
    case paused = "paused"
    case completed = "completed"
    case error = "error"
}

public enum ContentType: String, Codable, Sendable {
    case text = "text"
    case toolUse = "tool_use"
}

public enum WaitingReason: String, Codable, Sendable {
    case userInput = "user_input"
    case toolExecution = "tool_execution"
    case rateLimit = "rate_limit"
    case apiCall = "api_call"
}

public enum ConnectionQuality: String, Codable, Sendable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
}

public enum ErrorAction: String, Codable, Sendable {
    case retry = "retry"
    case restart = "restart"
    case abort = "abort"
    case ignore = "ignore"
}

public enum RiskLevel: String, Codable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

public enum LimitType: String, Codable, Sendable {
    case requests = "requests"
    case tokens = "tokens"
    case concurrent = "concurrent"
}

public enum TodoStatus: String, Codable, Sendable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
}

public enum QuestionType: String, Codable, Sendable {
    case confirmation = "confirmation"
    case mcq = "mcq"
    case textInput = "text_input"
}

// MARK: - Shared Types

public struct Attachment: Codable, Equatable, Sendable {
    public let type: AttachmentType
    public let data: String
    public let mimeType: String?
    public let filename: String?

    public init(type: AttachmentType, data: String, mimeType: String? = nil, filename: String? = nil) {
        self.type = type
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
    }
}

public struct TodoItem: Codable, Equatable, Sendable {
    public let id: String
    public let content: String
    public let status: TodoStatus

    public init(id: String, content: String, status: TodoStatus) {
        self.id = id
        self.content = content
        self.status = status
    }
}

public struct QuestionOption: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

// MARK: - Payload Types

public struct EmptyPayload: Codable, Equatable, Sendable {
    public init() {}
}

public struct PairRequestPayload: Codable, Equatable, Sendable {
    public let remoteDeviceName: String
    public let remoteDeviceId: String
    public let remotePublicKey: String

    public init(remoteDeviceName: String, remoteDeviceId: String, remotePublicKey: String) {
        self.remoteDeviceName = remoteDeviceName
        self.remoteDeviceId = remoteDeviceId
        self.remotePublicKey = remotePublicKey
    }
}

public struct PairAcceptedPayload: Codable, Equatable, Sendable {
    public let executorDeviceId: String
    public let executorPublicKey: String
    public let executorDeviceName: String

    public init(executorDeviceId: String, executorPublicKey: String, executorDeviceName: String) {
        self.executorDeviceId = executorDeviceId
        self.executorPublicKey = executorPublicKey
        self.executorDeviceName = executorDeviceName
    }
}

public struct SessionStopPayload: Codable, Equatable, Sendable {
    public let force: Bool?

    public init(force: Bool? = nil) {
        self.force = force
    }
}

public struct SessionCancelPayload: Codable, Equatable, Sendable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct UserPromptPayload: Codable, Equatable, Sendable {
    public let content: String
    public let attachments: [Attachment]?

    public init(content: String, attachments: [Attachment]? = nil) {
        self.content = content
        self.attachments = attachments
    }
}

public struct UserConfirmationPayload: Codable, Equatable, Sendable {
    public let questionId: String
    public let confirmed: Bool

    public init(questionId: String, confirmed: Bool) {
        self.questionId = questionId
        self.confirmed = confirmed
    }
}

public struct McqResponsePayload: Codable, Equatable, Sendable {
    public let questionId: String
    public let selectedOptionIds: [String]
    public let customAnswer: String?

    public init(questionId: String, selectedOptionIds: [String], customAnswer: String? = nil) {
        self.questionId = questionId
        self.selectedOptionIds = selectedOptionIds
        self.customAnswer = customAnswer
    }
}

public struct ToolApprovalPayload: Codable, Equatable, Sendable {
    public let toolUseId: String
    public let approved: Bool
    public let modifiedInput: String?

    public init(toolUseId: String, approved: Bool, modifiedInput: String? = nil) {
        self.toolUseId = toolUseId
        self.approved = approved
        self.modifiedInput = modifiedInput
    }
}

public struct WorktreeCreatePayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let branch: String

    public init(repoId: String, branch: String) {
        self.repoId = repoId
        self.branch = branch
    }
}

public struct ConflictsFixPayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let worktreeId: String

    public init(repoId: String, worktreeId: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
    }
}

public struct OutputChunkPayload: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ExecutionCompletedPayload: Codable, Equatable, Sendable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}

public struct WorktreeAddedPayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let worktreeId: String

    public init(repoId: String, worktreeId: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
    }
}

public struct RepositoryAddedPayload: Codable, Equatable, Sendable {
    public let repoId: String

    public init(repoId: String) {
        self.repoId = repoId
    }
}

public struct RepositoryRemovedPayload: Codable, Equatable, Sendable {
    public let repoId: String

    public init(repoId: String) {
        self.repoId = repoId
    }
}

public struct ConflictsFixedPayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let worktreeId: String

    public init(repoId: String, worktreeId: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
    }
}

public struct ConflictsFixFailedPayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let worktreeId: String

    public init(repoId: String, worktreeId: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
    }
}

public struct GitPushCompletedPayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let worktreeId: String

    public init(repoId: String, worktreeId: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
    }
}

public struct GitPushFailedPayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let worktreeId: String

    public init(repoId: String, worktreeId: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
    }
}

public struct ConflictsFoundPayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let worktreeId: String

    public init(repoId: String, worktreeId: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
    }
}

public struct ToolStartedPayload: Codable, Equatable, Sendable {
    public let toolUseId: String
    public let toolName: String
    public let input: String?

    public init(toolUseId: String, toolName: String, input: String? = nil) {
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.input = input
    }
}

public struct ToolOutputChunkPayload: Codable, Equatable, Sendable {
    public let toolUseId: String
    public let chunk: String
    public let sequenceNumber: Double
    public let isComplete: Bool

    public init(toolUseId: String, chunk: String, sequenceNumber: Double, isComplete: Bool) {
        self.toolUseId = toolUseId
        self.chunk = chunk
        self.sequenceNumber = sequenceNumber
        self.isComplete = isComplete
    }
}

public struct ToolCompletedPayload: Codable, Equatable, Sendable {
    public let toolUseId: String
    public let toolName: String
    public let output: String?
    public let success: Bool
    public let durationMs: Double

    public init(toolUseId: String, toolName: String, output: String? = nil, success: Bool, durationMs: Double) {
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.output = output
        self.success = success
        self.durationMs = durationMs
    }
}

public struct ToolFailedPayload: Codable, Equatable, Sendable {
    public let toolUseId: String
    public let toolName: String
    public let error: String
    public let errorCode: String?

    public init(toolUseId: String, toolName: String, error: String, errorCode: String? = nil) {
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.error = error
        self.errorCode = errorCode
    }
}

public struct ToolApprovalRequiredPayload: Codable, Equatable, Sendable {
    public let toolUseId: String
    public let toolName: String
    public let input: String
    public let description: String?
    public let risk: RiskLevel?

    public init(toolUseId: String, toolName: String, input: String, description: String? = nil, risk: RiskLevel? = nil) {
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.input = input
        self.description = description
        self.risk = risk
    }
}

public struct StreamingThinkingPayload: Codable, Equatable, Sendable {
    public let thinkingContent: String?

    public init(thinkingContent: String? = nil) {
        self.thinkingContent = thinkingContent
    }
}

public struct StreamingGeneratingPayload: Codable, Equatable, Sendable {
    public let contentType: ContentType

    public init(contentType: ContentType) {
        self.contentType = contentType
    }
}

public struct StreamingWaitingPayload: Codable, Equatable, Sendable {
    public let reason: WaitingReason

    public init(reason: WaitingReason) {
        self.reason = reason
    }
}

public struct FileCreatedPayload: Codable, Equatable, Sendable {
    public let filePath: String
    public let content: String?
    public let linesAdded: Double

    public init(filePath: String, content: String? = nil, linesAdded: Double) {
        self.filePath = filePath
        self.content = content
        self.linesAdded = linesAdded
    }
}

public struct FileModifiedPayload: Codable, Equatable, Sendable {
    public let filePath: String
    public let diff: String?
    public let linesAdded: Double
    public let linesRemoved: Double

    public init(filePath: String, diff: String? = nil, linesAdded: Double, linesRemoved: Double) {
        self.filePath = filePath
        self.diff = diff
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}

public struct FileDeletedPayload: Codable, Equatable, Sendable {
    public let filePath: String
    public let linesRemoved: Double

    public init(filePath: String, linesRemoved: Double) {
        self.filePath = filePath
        self.linesRemoved = linesRemoved
    }
}

public struct FileRenamedPayload: Codable, Equatable, Sendable {
    public let oldPath: String
    public let newPath: String

    public init(oldPath: String, newPath: String) {
        self.oldPath = oldPath
        self.newPath = newPath
    }
}

public struct SessionHeartbeatPayload: Codable, Equatable, Sendable {
    public let processAlive: Bool
    public let memoryUsageMb: Double?
    public let cpuPercent: Double?
    public let uptime: Double

    public init(processAlive: Bool, memoryUsageMb: Double? = nil, cpuPercent: Double? = nil, uptime: Double) {
        self.processAlive = processAlive
        self.memoryUsageMb = memoryUsageMb
        self.cpuPercent = cpuPercent
        self.uptime = uptime
    }
}

public struct SessionStateChangedPayload: Codable, Equatable, Sendable {
    public let previousState: SessionState
    public let newState: SessionState
    public let reason: String?

    public init(previousState: SessionState, newState: SessionState, reason: String? = nil) {
        self.previousState = previousState
        self.newState = newState
        self.reason = reason
    }
}

public struct ConnectionQualityPayload: Codable, Equatable, Sendable {
    public let latencyMs: Double
    public let packetLossPercent: Double
    public let quality: ConnectionQuality

    public init(latencyMs: Double, packetLossPercent: Double, quality: ConnectionQuality) {
        self.latencyMs = latencyMs
        self.packetLossPercent = packetLossPercent
        self.quality = quality
    }
}

public struct SessionErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let details: String?
    public let recoverable: Bool
    public let action: ErrorAction?

    public init(code: String, message: String, details: String? = nil, recoverable: Bool, action: ErrorAction? = nil) {
        self.code = code
        self.message = message
        self.details = details
        self.recoverable = recoverable
        self.action = action
    }
}

public struct SessionWarningPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let details: String?

    public init(code: String, message: String, details: String? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

public struct RateLimitWarningPayload: Codable, Equatable, Sendable {
    public let retryAfterMs: Double
    public let limitType: LimitType

    public init(retryAfterMs: Double, limitType: LimitType) {
        self.retryAfterMs = retryAfterMs
        self.limitType = limitType
    }
}

public struct TodoListUpdatedPayload: Codable, Equatable, Sendable {
    public let items: [TodoItem]

    public init(items: [TodoItem]) {
        self.items = items
    }
}

public struct TodoItemUpdatedPayload: Codable, Equatable, Sendable {
    public let itemId: String
    public let content: String
    public let previousStatus: TodoStatus
    public let newStatus: TodoStatus

    public init(itemId: String, content: String, previousStatus: TodoStatus, newStatus: TodoStatus) {
        self.itemId = itemId
        self.content = content
        self.previousStatus = previousStatus
        self.newStatus = newStatus
    }
}

public struct QuestionAskedPayload: Codable, Equatable, Sendable {
    public let questionId: String
    public let questionType: QuestionType
    public let question: String
    public let options: [QuestionOption]?
    public let allowsMultiSelect: Bool?
    public let allowsCustomAnswer: Bool?
    public let defaultValue: String?

    public init(questionId: String, questionType: QuestionType, question: String, options: [QuestionOption]? = nil, allowsMultiSelect: Bool? = nil, allowsCustomAnswer: Bool? = nil, defaultValue: String? = nil) {
        self.questionId = questionId
        self.questionType = questionType
        self.question = question
        self.options = options
        self.allowsMultiSelect = allowsMultiSelect
        self.allowsCustomAnswer = allowsCustomAnswer
        self.defaultValue = defaultValue
    }
}

public struct QuestionAnsweredPayload: Codable, Equatable, Sendable {
    public let questionId: String
    public let selectedOptionIds: [String]?
    public let textResponse: String?
    public let answeredBy: String

    public init(questionId: String, selectedOptionIds: [String]? = nil, textResponse: String? = nil, answeredBy: String) {
        self.questionId = questionId
        self.selectedOptionIds = selectedOptionIds
        self.textResponse = textResponse
        self.answeredBy = answeredBy
    }
}

// MARK: - Concrete Event Types

// MARK: Handshake Events

public struct PairRequestEvent: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: HandshakeEventType
    public let plane: Plane
    public let sessionId: String?
    public let payload: PairRequestPayload

    public init(eventId: String, createdAt: Double, payload: PairRequestPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .pairRequest
        self.plane = .handshake
        self.sessionId = nil
        self.payload = payload
    }
}

public struct PairAcceptedEvent: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: HandshakeEventType
    public let plane: Plane
    public let sessionId: String?
    public let payload: PairAcceptedPayload

    public init(eventId: String, createdAt: Double, payload: PairAcceptedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .pairAccepted
        self.plane = .handshake
        self.sessionId = nil
        self.payload = payload
    }
}

public struct SessionCreatedEvent: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: HandshakeEventType
    public let plane: Plane
    public let sessionId: String
    public let payload: EmptyPayload

    public init(eventId: String, createdAt: Double, sessionId: String) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionCreated
        self.plane = .handshake
        self.sessionId = sessionId
        self.payload = EmptyPayload()
    }
}

// MARK: Session Control Commands

public struct SessionPauseCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: EmptyPayload

    public init(eventId: String, createdAt: Double, sessionId: String) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionPauseCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = EmptyPayload()
    }
}

public struct SessionResumeCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: EmptyPayload

    public init(eventId: String, createdAt: Double, sessionId: String) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionResumeCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = EmptyPayload()
    }
}

public struct SessionStopCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: SessionStopPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: SessionStopPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionStopCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = payload
    }
}

public struct SessionCancelCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: SessionCancelPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: SessionCancelPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionCancelCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = payload
    }
}

// MARK: User Input Commands

public struct UserPromptCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: UserPromptPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: UserPromptPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .userPromptCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = payload
    }
}

public struct UserConfirmationCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: UserConfirmationPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: UserConfirmationPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .userConfirmationCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = payload
    }
}

public struct McqResponseCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: McqResponsePayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: McqResponsePayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .mcqResponseCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = payload
    }
}

public struct ToolApprovalCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ToolApprovalPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ToolApprovalPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .toolApprovalCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = payload
    }
}

// MARK: Worktree/Conflicts Commands

public struct WorktreeCreateCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: WorktreeCreatePayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: WorktreeCreatePayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .worktreeCreateCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = payload
    }
}

public struct ConflictsFixCommand: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ConflictsFixPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ConflictsFixPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .conflictsFixCommand
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .remoteCommand
        self.payload = payload
    }
}

// MARK: Execution Updates

public struct ExecutionStartedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: EmptyPayload

    public init(eventId: String, createdAt: Double, sessionId: String) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .executionStarted
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = EmptyPayload()
    }
}

public struct OutputChunkUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: OutputChunkPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: OutputChunkPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .outputChunk
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ExecutionCompletedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ExecutionCompletedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ExecutionCompletedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .executionCompleted
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct WorktreeAddedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: WorktreeAddedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: WorktreeAddedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .worktreeAdded
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct RepositoryAddedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: RepositoryAddedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: RepositoryAddedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .repositoryAdded
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct RepositoryRemovedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: RepositoryRemovedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: RepositoryRemovedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .repositoryRemoved
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ConflictsFixedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ConflictsFixedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ConflictsFixedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .conflictsFixed
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ConflictsFixFailedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ConflictsFixFailedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ConflictsFixFailedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .conflictsFixFailed
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct GitPushCompletedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: GitPushCompletedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: GitPushCompletedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .gitPushCompleted
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct GitPushFailedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: GitPushFailedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: GitPushFailedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .gitPushFailed
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ConflictsFoundUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ConflictsFoundPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ConflictsFoundPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .conflictsFound
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

// MARK: Tool Execution Updates

public struct ToolStartedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ToolStartedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ToolStartedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .toolStarted
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ToolOutputChunkUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ToolOutputChunkPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ToolOutputChunkPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .toolOutputChunk
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ToolCompletedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ToolCompletedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ToolCompletedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .toolCompleted
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ToolFailedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ToolFailedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ToolFailedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .toolFailed
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ToolApprovalRequiredUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ToolApprovalRequiredPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ToolApprovalRequiredPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .toolApprovalRequired
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

// MARK: Streaming State Updates

public struct StreamingThinkingUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: StreamingThinkingPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: StreamingThinkingPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .streamingThinking
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct StreamingGeneratingUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: StreamingGeneratingPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: StreamingGeneratingPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .streamingGenerating
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct StreamingWaitingUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: StreamingWaitingPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: StreamingWaitingPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .streamingWaiting
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct StreamingIdleUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: EmptyPayload

    public init(eventId: String, createdAt: Double, sessionId: String) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .streamingIdle
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = EmptyPayload()
    }
}

// MARK: File Change Updates

public struct FileCreatedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: FileCreatedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: FileCreatedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .fileCreated
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct FileModifiedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: FileModifiedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: FileModifiedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .fileModified
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct FileDeletedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: FileDeletedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: FileDeletedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .fileDeleted
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct FileRenamedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: FileRenamedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: FileRenamedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .fileRenamed
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

// MARK: Session Health Updates

public struct SessionHeartbeatUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: SessionHeartbeatPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: SessionHeartbeatPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionHeartbeat
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct SessionStateChangedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: SessionStateChangedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: SessionStateChangedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionStateChanged
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct ConnectionQualityUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: ConnectionQualityPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: ConnectionQualityPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .connectionQualityUpdate
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

// MARK: Error/Warning Updates

public struct SessionErrorUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: SessionErrorPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: SessionErrorPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionError
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct SessionWarningUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: SessionWarningPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: SessionWarningPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionWarning
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct RateLimitWarningUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: RateLimitWarningPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: RateLimitWarningPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .rateLimitWarning
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

// MARK: Todo Updates

public struct TodoListUpdatedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: TodoListUpdatedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: TodoListUpdatedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .todoListUpdated
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct TodoItemUpdatedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: TodoItemUpdatedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: TodoItemUpdatedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .todoItemUpdated
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

// MARK: Question Events

public struct QuestionAskedUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: QuestionAskedPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: QuestionAskedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .questionAsked
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

public struct QuestionAnsweredUpdate: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: SessionEventTypeValue
    public let plane: Plane
    public let sessionId: String
    public let sessionEventType: SessionEventType
    public let payload: QuestionAnsweredPayload

    public init(eventId: String, createdAt: Double, sessionId: String, payload: QuestionAnsweredPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .questionAnswered
        self.plane = .session
        self.sessionId = sessionId
        self.sessionEventType = .executorUpdate
        self.payload = payload
    }
}

// MARK: ACK Frame

public struct AckFrame: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String

    public init(eventId: String) {
        self.opcode = .ack
        self.eventId = eventId
    }
}

// MARK: - Discriminated Unions

public enum HandshakeEvent: Equatable, Sendable {
    case pairRequest(PairRequestEvent)
    case pairAccepted(PairAcceptedEvent)
    case sessionCreated(SessionCreatedEvent)
}

public enum SessionEvent: Equatable, Sendable {
    // Session Control Commands
    case sessionPauseCommand(SessionPauseCommand)
    case sessionResumeCommand(SessionResumeCommand)
    case sessionStopCommand(SessionStopCommand)
    case sessionCancelCommand(SessionCancelCommand)
    // User Input Commands
    case userPromptCommand(UserPromptCommand)
    case userConfirmationCommand(UserConfirmationCommand)
    case mcqResponseCommand(McqResponseCommand)
    case toolApprovalCommand(ToolApprovalCommand)
    // Worktree/Conflicts Commands
    case worktreeCreateCommand(WorktreeCreateCommand)
    case conflictsFixCommand(ConflictsFixCommand)
    // Execution Updates
    case executionStarted(ExecutionStartedUpdate)
    case outputChunk(OutputChunkUpdate)
    case executionCompleted(ExecutionCompletedUpdate)
    case worktreeAdded(WorktreeAddedUpdate)
    case repositoryAdded(RepositoryAddedUpdate)
    case repositoryRemoved(RepositoryRemovedUpdate)
    case conflictsFixed(ConflictsFixedUpdate)
    case conflictsFixFailed(ConflictsFixFailedUpdate)
    case gitPushCompleted(GitPushCompletedUpdate)
    case gitPushFailed(GitPushFailedUpdate)
    case conflictsFound(ConflictsFoundUpdate)
    // Tool Execution Updates
    case toolStarted(ToolStartedUpdate)
    case toolOutputChunk(ToolOutputChunkUpdate)
    case toolCompleted(ToolCompletedUpdate)
    case toolFailed(ToolFailedUpdate)
    case toolApprovalRequired(ToolApprovalRequiredUpdate)
    // Streaming State Updates
    case streamingThinking(StreamingThinkingUpdate)
    case streamingGenerating(StreamingGeneratingUpdate)
    case streamingWaiting(StreamingWaitingUpdate)
    case streamingIdle(StreamingIdleUpdate)
    // File Change Updates
    case fileCreated(FileCreatedUpdate)
    case fileModified(FileModifiedUpdate)
    case fileDeleted(FileDeletedUpdate)
    case fileRenamed(FileRenamedUpdate)
    // Session Health Updates
    case sessionHeartbeat(SessionHeartbeatUpdate)
    case sessionStateChanged(SessionStateChangedUpdate)
    case connectionQualityUpdate(ConnectionQualityUpdate)
    // Error/Warning Updates
    case sessionError(SessionErrorUpdate)
    case sessionWarning(SessionWarningUpdate)
    case rateLimitWarning(RateLimitWarningUpdate)
    // Todo Updates
    case todoListUpdated(TodoListUpdatedUpdate)
    case todoItemUpdated(TodoItemUpdatedUpdate)
    // Question Events
    case questionAsked(QuestionAskedUpdate)
    case questionAnswered(QuestionAnsweredUpdate)
}

public enum UnboundEvent: Equatable, Sendable {
    case handshake(HandshakeEvent)
    case session(SessionEvent)
}

public enum AnyEvent: Equatable, Sendable {
    case event(UnboundEvent)
    case ack(AckFrame)
}

// MARK: - Codable Extensions for Discriminated Unions

extension HandshakeEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(HandshakeEventType.self, forKey: .type)

        switch type {
        case .pairRequest:
            self = .pairRequest(try PairRequestEvent(from: decoder))
        case .pairAccepted:
            self = .pairAccepted(try PairAcceptedEvent(from: decoder))
        case .sessionCreated:
            self = .sessionCreated(try SessionCreatedEvent(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .pairRequest(let event):
            try event.encode(to: encoder)
        case .pairAccepted(let event):
            try event.encode(to: encoder)
        case .sessionCreated(let event):
            try event.encode(to: encoder)
        }
    }
}

extension SessionEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SessionEventTypeValue.self, forKey: .type)

        switch type {
        // Session Control Commands
        case .sessionPauseCommand:
            self = .sessionPauseCommand(try SessionPauseCommand(from: decoder))
        case .sessionResumeCommand:
            self = .sessionResumeCommand(try SessionResumeCommand(from: decoder))
        case .sessionStopCommand:
            self = .sessionStopCommand(try SessionStopCommand(from: decoder))
        case .sessionCancelCommand:
            self = .sessionCancelCommand(try SessionCancelCommand(from: decoder))
        // User Input Commands
        case .userPromptCommand:
            self = .userPromptCommand(try UserPromptCommand(from: decoder))
        case .userConfirmationCommand:
            self = .userConfirmationCommand(try UserConfirmationCommand(from: decoder))
        case .mcqResponseCommand:
            self = .mcqResponseCommand(try McqResponseCommand(from: decoder))
        case .toolApprovalCommand:
            self = .toolApprovalCommand(try ToolApprovalCommand(from: decoder))
        // Worktree/Conflicts Commands
        case .worktreeCreateCommand:
            self = .worktreeCreateCommand(try WorktreeCreateCommand(from: decoder))
        case .conflictsFixCommand:
            self = .conflictsFixCommand(try ConflictsFixCommand(from: decoder))
        // Execution Updates
        case .executionStarted:
            self = .executionStarted(try ExecutionStartedUpdate(from: decoder))
        case .outputChunk:
            self = .outputChunk(try OutputChunkUpdate(from: decoder))
        case .executionCompleted:
            self = .executionCompleted(try ExecutionCompletedUpdate(from: decoder))
        case .worktreeAdded:
            self = .worktreeAdded(try WorktreeAddedUpdate(from: decoder))
        case .repositoryAdded:
            self = .repositoryAdded(try RepositoryAddedUpdate(from: decoder))
        case .repositoryRemoved:
            self = .repositoryRemoved(try RepositoryRemovedUpdate(from: decoder))
        case .conflictsFixed:
            self = .conflictsFixed(try ConflictsFixedUpdate(from: decoder))
        case .conflictsFixFailed:
            self = .conflictsFixFailed(try ConflictsFixFailedUpdate(from: decoder))
        case .gitPushCompleted:
            self = .gitPushCompleted(try GitPushCompletedUpdate(from: decoder))
        case .gitPushFailed:
            self = .gitPushFailed(try GitPushFailedUpdate(from: decoder))
        case .conflictsFound:
            self = .conflictsFound(try ConflictsFoundUpdate(from: decoder))
        // Tool Execution Updates
        case .toolStarted:
            self = .toolStarted(try ToolStartedUpdate(from: decoder))
        case .toolOutputChunk:
            self = .toolOutputChunk(try ToolOutputChunkUpdate(from: decoder))
        case .toolCompleted:
            self = .toolCompleted(try ToolCompletedUpdate(from: decoder))
        case .toolFailed:
            self = .toolFailed(try ToolFailedUpdate(from: decoder))
        case .toolApprovalRequired:
            self = .toolApprovalRequired(try ToolApprovalRequiredUpdate(from: decoder))
        // Streaming State Updates
        case .streamingThinking:
            self = .streamingThinking(try StreamingThinkingUpdate(from: decoder))
        case .streamingGenerating:
            self = .streamingGenerating(try StreamingGeneratingUpdate(from: decoder))
        case .streamingWaiting:
            self = .streamingWaiting(try StreamingWaitingUpdate(from: decoder))
        case .streamingIdle:
            self = .streamingIdle(try StreamingIdleUpdate(from: decoder))
        // File Change Updates
        case .fileCreated:
            self = .fileCreated(try FileCreatedUpdate(from: decoder))
        case .fileModified:
            self = .fileModified(try FileModifiedUpdate(from: decoder))
        case .fileDeleted:
            self = .fileDeleted(try FileDeletedUpdate(from: decoder))
        case .fileRenamed:
            self = .fileRenamed(try FileRenamedUpdate(from: decoder))
        // Session Health Updates
        case .sessionHeartbeat:
            self = .sessionHeartbeat(try SessionHeartbeatUpdate(from: decoder))
        case .sessionStateChanged:
            self = .sessionStateChanged(try SessionStateChangedUpdate(from: decoder))
        case .connectionQualityUpdate:
            self = .connectionQualityUpdate(try ConnectionQualityUpdate(from: decoder))
        // Error/Warning Updates
        case .sessionError:
            self = .sessionError(try SessionErrorUpdate(from: decoder))
        case .sessionWarning:
            self = .sessionWarning(try SessionWarningUpdate(from: decoder))
        case .rateLimitWarning:
            self = .rateLimitWarning(try RateLimitWarningUpdate(from: decoder))
        // Todo Updates
        case .todoListUpdated:
            self = .todoListUpdated(try TodoListUpdatedUpdate(from: decoder))
        case .todoItemUpdated:
            self = .todoItemUpdated(try TodoItemUpdatedUpdate(from: decoder))
        // Question Events
        case .questionAsked:
            self = .questionAsked(try QuestionAskedUpdate(from: decoder))
        case .questionAnswered:
            self = .questionAnswered(try QuestionAnsweredUpdate(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        // Session Control Commands
        case .sessionPauseCommand(let event):
            try event.encode(to: encoder)
        case .sessionResumeCommand(let event):
            try event.encode(to: encoder)
        case .sessionStopCommand(let event):
            try event.encode(to: encoder)
        case .sessionCancelCommand(let event):
            try event.encode(to: encoder)
        // User Input Commands
        case .userPromptCommand(let event):
            try event.encode(to: encoder)
        case .userConfirmationCommand(let event):
            try event.encode(to: encoder)
        case .mcqResponseCommand(let event):
            try event.encode(to: encoder)
        case .toolApprovalCommand(let event):
            try event.encode(to: encoder)
        // Worktree/Conflicts Commands
        case .worktreeCreateCommand(let event):
            try event.encode(to: encoder)
        case .conflictsFixCommand(let event):
            try event.encode(to: encoder)
        // Execution Updates
        case .executionStarted(let event):
            try event.encode(to: encoder)
        case .outputChunk(let event):
            try event.encode(to: encoder)
        case .executionCompleted(let event):
            try event.encode(to: encoder)
        case .worktreeAdded(let event):
            try event.encode(to: encoder)
        case .repositoryAdded(let event):
            try event.encode(to: encoder)
        case .repositoryRemoved(let event):
            try event.encode(to: encoder)
        case .conflictsFixed(let event):
            try event.encode(to: encoder)
        case .conflictsFixFailed(let event):
            try event.encode(to: encoder)
        case .gitPushCompleted(let event):
            try event.encode(to: encoder)
        case .gitPushFailed(let event):
            try event.encode(to: encoder)
        case .conflictsFound(let event):
            try event.encode(to: encoder)
        // Tool Execution Updates
        case .toolStarted(let event):
            try event.encode(to: encoder)
        case .toolOutputChunk(let event):
            try event.encode(to: encoder)
        case .toolCompleted(let event):
            try event.encode(to: encoder)
        case .toolFailed(let event):
            try event.encode(to: encoder)
        case .toolApprovalRequired(let event):
            try event.encode(to: encoder)
        // Streaming State Updates
        case .streamingThinking(let event):
            try event.encode(to: encoder)
        case .streamingGenerating(let event):
            try event.encode(to: encoder)
        case .streamingWaiting(let event):
            try event.encode(to: encoder)
        case .streamingIdle(let event):
            try event.encode(to: encoder)
        // File Change Updates
        case .fileCreated(let event):
            try event.encode(to: encoder)
        case .fileModified(let event):
            try event.encode(to: encoder)
        case .fileDeleted(let event):
            try event.encode(to: encoder)
        case .fileRenamed(let event):
            try event.encode(to: encoder)
        // Session Health Updates
        case .sessionHeartbeat(let event):
            try event.encode(to: encoder)
        case .sessionStateChanged(let event):
            try event.encode(to: encoder)
        case .connectionQualityUpdate(let event):
            try event.encode(to: encoder)
        // Error/Warning Updates
        case .sessionError(let event):
            try event.encode(to: encoder)
        case .sessionWarning(let event):
            try event.encode(to: encoder)
        case .rateLimitWarning(let event):
            try event.encode(to: encoder)
        // Todo Updates
        case .todoListUpdated(let event):
            try event.encode(to: encoder)
        case .todoItemUpdated(let event):
            try event.encode(to: encoder)
        // Question Events
        case .questionAsked(let event):
            try event.encode(to: encoder)
        case .questionAnswered(let event):
            try event.encode(to: encoder)
        }
    }
}

extension UnboundEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case plane
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let plane = try container.decode(Plane.self, forKey: .plane)

        switch plane {
        case .handshake:
            self = .handshake(try HandshakeEvent(from: decoder))
        case .session:
            self = .session(try SessionEvent(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .handshake(let event):
            try event.encode(to: encoder)
        case .session(let event):
            try event.encode(to: encoder)
        }
    }
}

extension AnyEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case opcode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let opcode = try container.decode(Opcode.self, forKey: .opcode)

        switch opcode {
        case .event:
            self = .event(try UnboundEvent(from: decoder))
        case .ack:
            self = .ack(try AckFrame(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .event(let event):
            try event.encode(to: encoder)
        case .ack(let frame):
            try frame.encode(to: encoder)
        }
    }
}

// MARK: - Convenience Extensions

extension AnyEvent {
    public var eventId: String {
        switch self {
        case .event(let unboundEvent):
            return unboundEvent.eventId
        case .ack(let ackFrame):
            return ackFrame.eventId
        }
    }
}

extension UnboundEvent {
    public var eventId: String {
        switch self {
        case .handshake(let event):
            return event.eventId
        case .session(let event):
            return event.eventId
        }
    }
}

extension HandshakeEvent {
    public var eventId: String {
        switch self {
        case .pairRequest(let event):
            return event.eventId
        case .pairAccepted(let event):
            return event.eventId
        case .sessionCreated(let event):
            return event.eventId
        }
    }
}

extension SessionEvent {
    public var eventId: String {
        switch self {
        // Session Control Commands
        case .sessionPauseCommand(let event):
            return event.eventId
        case .sessionResumeCommand(let event):
            return event.eventId
        case .sessionStopCommand(let event):
            return event.eventId
        case .sessionCancelCommand(let event):
            return event.eventId
        // User Input Commands
        case .userPromptCommand(let event):
            return event.eventId
        case .userConfirmationCommand(let event):
            return event.eventId
        case .mcqResponseCommand(let event):
            return event.eventId
        case .toolApprovalCommand(let event):
            return event.eventId
        // Worktree/Conflicts Commands
        case .worktreeCreateCommand(let event):
            return event.eventId
        case .conflictsFixCommand(let event):
            return event.eventId
        // Execution Updates
        case .executionStarted(let event):
            return event.eventId
        case .outputChunk(let event):
            return event.eventId
        case .executionCompleted(let event):
            return event.eventId
        case .worktreeAdded(let event):
            return event.eventId
        case .repositoryAdded(let event):
            return event.eventId
        case .repositoryRemoved(let event):
            return event.eventId
        case .conflictsFixed(let event):
            return event.eventId
        case .conflictsFixFailed(let event):
            return event.eventId
        case .gitPushCompleted(let event):
            return event.eventId
        case .gitPushFailed(let event):
            return event.eventId
        case .conflictsFound(let event):
            return event.eventId
        // Tool Execution Updates
        case .toolStarted(let event):
            return event.eventId
        case .toolOutputChunk(let event):
            return event.eventId
        case .toolCompleted(let event):
            return event.eventId
        case .toolFailed(let event):
            return event.eventId
        case .toolApprovalRequired(let event):
            return event.eventId
        // Streaming State Updates
        case .streamingThinking(let event):
            return event.eventId
        case .streamingGenerating(let event):
            return event.eventId
        case .streamingWaiting(let event):
            return event.eventId
        case .streamingIdle(let event):
            return event.eventId
        // File Change Updates
        case .fileCreated(let event):
            return event.eventId
        case .fileModified(let event):
            return event.eventId
        case .fileDeleted(let event):
            return event.eventId
        case .fileRenamed(let event):
            return event.eventId
        // Session Health Updates
        case .sessionHeartbeat(let event):
            return event.eventId
        case .sessionStateChanged(let event):
            return event.eventId
        case .connectionQualityUpdate(let event):
            return event.eventId
        // Error/Warning Updates
        case .sessionError(let event):
            return event.eventId
        case .sessionWarning(let event):
            return event.eventId
        case .rateLimitWarning(let event):
            return event.eventId
        // Todo Updates
        case .todoListUpdated(let event):
            return event.eventId
        case .todoItemUpdated(let event):
            return event.eventId
        // Question Events
        case .questionAsked(let event):
            return event.eventId
        case .questionAnswered(let event):
            return event.eventId
        }
    }

    public var sessionId: String {
        switch self {
        // Session Control Commands
        case .sessionPauseCommand(let event):
            return event.sessionId
        case .sessionResumeCommand(let event):
            return event.sessionId
        case .sessionStopCommand(let event):
            return event.sessionId
        case .sessionCancelCommand(let event):
            return event.sessionId
        // User Input Commands
        case .userPromptCommand(let event):
            return event.sessionId
        case .userConfirmationCommand(let event):
            return event.sessionId
        case .mcqResponseCommand(let event):
            return event.sessionId
        case .toolApprovalCommand(let event):
            return event.sessionId
        // Worktree/Conflicts Commands
        case .worktreeCreateCommand(let event):
            return event.sessionId
        case .conflictsFixCommand(let event):
            return event.sessionId
        // Execution Updates
        case .executionStarted(let event):
            return event.sessionId
        case .outputChunk(let event):
            return event.sessionId
        case .executionCompleted(let event):
            return event.sessionId
        case .worktreeAdded(let event):
            return event.sessionId
        case .repositoryAdded(let event):
            return event.sessionId
        case .repositoryRemoved(let event):
            return event.sessionId
        case .conflictsFixed(let event):
            return event.sessionId
        case .conflictsFixFailed(let event):
            return event.sessionId
        case .gitPushCompleted(let event):
            return event.sessionId
        case .gitPushFailed(let event):
            return event.sessionId
        case .conflictsFound(let event):
            return event.sessionId
        // Tool Execution Updates
        case .toolStarted(let event):
            return event.sessionId
        case .toolOutputChunk(let event):
            return event.sessionId
        case .toolCompleted(let event):
            return event.sessionId
        case .toolFailed(let event):
            return event.sessionId
        case .toolApprovalRequired(let event):
            return event.sessionId
        // Streaming State Updates
        case .streamingThinking(let event):
            return event.sessionId
        case .streamingGenerating(let event):
            return event.sessionId
        case .streamingWaiting(let event):
            return event.sessionId
        case .streamingIdle(let event):
            return event.sessionId
        // File Change Updates
        case .fileCreated(let event):
            return event.sessionId
        case .fileModified(let event):
            return event.sessionId
        case .fileDeleted(let event):
            return event.sessionId
        case .fileRenamed(let event):
            return event.sessionId
        // Session Health Updates
        case .sessionHeartbeat(let event):
            return event.sessionId
        case .sessionStateChanged(let event):
            return event.sessionId
        case .connectionQualityUpdate(let event):
            return event.sessionId
        // Error/Warning Updates
        case .sessionError(let event):
            return event.sessionId
        case .sessionWarning(let event):
            return event.sessionId
        case .rateLimitWarning(let event):
            return event.sessionId
        // Todo Updates
        case .todoListUpdated(let event):
            return event.sessionId
        case .todoItemUpdated(let event):
            return event.sessionId
        // Question Events
        case .questionAsked(let event):
            return event.sessionId
        case .questionAnswered(let event):
            return event.sessionId
        }
    }
}
