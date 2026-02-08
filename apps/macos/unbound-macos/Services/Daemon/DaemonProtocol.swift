//
//  DaemonProtocol.swift
//  unbound-macos
//
//  IPC protocol types matching daemon-ipc/src/protocol.rs
//  Uses JSON-RPC-like protocol over Unix domain sockets.
//

import Foundation

// MARK: - IPC Method Types

/// IPC methods available on the daemon.
/// Matches daemon-ipc/src/protocol.rs Method enum.
enum DaemonMethod: String, Codable {
    // Health
    case health
    case shutdown

    // Authentication
    case authStatus = "auth.status"
    case authLogin = "auth.login"
    case authCompleteSocial = "auth.complete_social"
    case authLogout = "auth.logout"

    // Sessions
    case sessionList = "session.list"
    case sessionCreate = "session.create"
    case sessionGet = "session.get"
    case sessionDelete = "session.delete"

    // Messages
    case messageList = "message.list"
    case messageSend = "message.send"

    // Repositories
    case repositoryList = "repository.list"
    case repositoryAdd = "repository.add"
    case repositoryRemove = "repository.remove"
    case repositoryListFiles = "repository.list_files"
    case repositoryReadFile = "repository.read_file"
    case repositoryReadFileSlice = "repository.read_file_slice"
    case repositoryWriteFile = "repository.write_file"
    case repositoryReplaceFileRange = "repository.replace_file_range"

    // Claude CLI
    case claudeSend = "claude.send"
    case claudeStatus = "claude.status"
    case claudeStop = "claude.stop"

    // Subscriptions (streaming)
    case sessionSubscribe = "session.subscribe"
    case sessionUnsubscribe = "session.unsubscribe"

    // Git operations
    case gitStatus = "git.status"
    case gitDiffFile = "git.diff_file"
    case gitLog = "git.log"
    case gitBranches = "git.branches"
    case gitStage = "git.stage"
    case gitUnstage = "git.unstage"
    case gitDiscard = "git.discard"
    case gitCommit = "git.commit"
    case gitPush = "git.push"

    // Terminal operations
    case terminalRun = "terminal.run"
    case terminalStatus = "terminal.status"
    case terminalStop = "terminal.stop"
}

// MARK: - Event Types

/// Types of events that can be pushed to subscribers.
/// Matches daemon-ipc/src/protocol.rs EventType enum.
enum DaemonEventType: String, Codable {
    /// New message added to session.
    case message
    /// Streaming content chunk (not stored, for real-time display).
    case streamingChunk = "streaming_chunk"
    /// Claude status changed (started/stopped).
    case statusChange = "status_change"
    /// Initial state dump on subscribe.
    case initialState = "initial_state"
    /// Keepalive ping.
    case ping
    /// Terminal output chunk (stdout or stderr).
    case terminalOutput = "terminal_output"
    /// Terminal command finished with exit code.
    case terminalFinished = "terminal_finished"
    /// Raw Claude NDJSON event (TUI parses typed messages from this).
    case claudeEvent = "claude_event"
    /// Claude streaming content (for real-time display).
    case claudeStreaming = "claude_streaming"
    /// Claude system event.
    case claudeSystem = "claude_system"
    /// Claude assistant event.
    case claudeAssistant = "claude_assistant"
    /// Claude user event.
    case claudeUser = "claude_user"
    /// Claude result event.
    case claudeResult = "claude_result"
    /// Auth state changed event.
    case authStateChanged = "auth_state_changed"
    /// Session created event.
    case sessionCreated = "session_created"
    /// Session deleted event.
    case sessionDeleted = "session_deleted"
}

// MARK: - Request

/// IPC request message.
struct DaemonRequest: Codable {
    /// Request ID for correlation.
    let id: String
    /// Method to invoke.
    let method: DaemonMethod
    /// Method parameters (optional).
    let params: [String: AnyCodableValue]?

    init(method: DaemonMethod, params: [String: Any]? = nil) {
        self.id = UUID().uuidString
        self.method = method
        self.params = params?.mapValues { AnyCodableValue($0) }
    }

    /// Serialize to JSON string with newline (NDJSON format).
    func toJsonLine() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DaemonError.encodingFailed
        }
        return json + "\n"
    }
}

// MARK: - Response

/// IPC response message.
struct DaemonResponse: Codable {
    /// Request ID for correlation.
    let id: String
    /// Result data (if successful).
    let result: AnyCodableValue?
    /// Error information (if failed).
    let error: DaemonErrorInfo?

    /// Check if the response is successful.
    var isSuccess: Bool {
        error == nil
    }

    /// Get result as specific type.
    func resultAs<T: Decodable>(_ type: T.Type) throws -> T {
        guard let result else {
            throw DaemonError.noResult
        }
        let data = try JSONSerialization.data(withJSONObject: result.value)
        return try JSONDecoder().decode(type, from: data)
    }

    /// Get result as dictionary.
    func resultAsDict() -> [String: Any]? {
        result?.value as? [String: Any]
    }
}

/// Error information in a response.
struct DaemonErrorInfo: Codable {
    /// Error code.
    let code: Int
    /// Error message.
    let message: String
    /// Additional error data.
    let data: AnyCodableValue?
}

// MARK: - Event

/// Server-push event for subscriptions.
struct DaemonEvent: Codable {
    /// Event type.
    let type: DaemonEventType
    /// Session ID this event relates to.
    let sessionId: String
    /// Event payload.
    let data: [String: AnyCodableValue]
    /// Sequence number for ordering/resumption.
    let sequence: Int64

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case data
        case sequence
    }

    /// Create a new DaemonEvent (used by shared memory consumer).
    init(type: DaemonEventType, sessionId: String, data: [String: AnyCodableValue], sequence: Int64) {
        self.type = type
        self.sessionId = sessionId
        self.data = data
        self.sequence = sequence
    }

    /// Get data value for key.
    func dataValue<T>(for key: String) -> T? {
        data[key]?.value as? T
    }

    /// Get raw NDJSON content for claude events.
    var rawClaudeEvent: String? {
        dataValue(for: "raw")
    }

    /// Get streaming content chunk.
    var streamingContent: String? {
        dataValue(for: "content")
    }

    /// Get status string for status change events.
    var statusValue: String? {
        dataValue(for: "status")
    }
}

// MARK: - Error Codes

/// Standard JSON-RPC error codes.
enum DaemonErrorCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
    // Custom error codes
    static let notAuthenticated = -32001
    static let notFound = -32002
    static let conflict = -32003
}

// MARK: - Daemon Errors

/// Errors that can occur when communicating with the daemon.
enum DaemonError: LocalizedError {
    case socketNotFound
    case connectionFailed(String)
    case encodingFailed
    case decodingFailed(String)
    case requestTimeout
    case noResult
    case serverError(code: Int, message: String)
    case notAuthenticated
    case notFound(String)
    case conflict(currentRevision: DaemonFileRevision?)
    case disconnected
    case daemonNotRunning

    var errorDescription: String? {
        switch self {
        case .socketNotFound:
            return "Daemon socket not found. Is the daemon running?"
        case .connectionFailed(let reason):
            return "Failed to connect to daemon: \(reason)"
        case .encodingFailed:
            return "Failed to encode request"
        case .decodingFailed(let reason):
            return "Failed to decode response: \(reason)"
        case .requestTimeout:
            return "Request timed out"
        case .noResult:
            return "No result in response"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .notAuthenticated:
            return "Not authenticated"
        case .notFound(let resource):
            return "Not found: \(resource)"
        case .conflict:
            return "File has changed on disk"
        case .disconnected:
            return "Disconnected from daemon"
        case .daemonNotRunning:
            return "Daemon is not running"
        }
    }
}

// MARK: - Type-Erased Codable Value

/// Type-erased wrapper for JSON values in request params and response data.
struct AnyCodableValue: Codable {
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
        } else if let int64 = try? container.decode(Int64.self) {
            value = int64
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodableValue].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON type"
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
        case let int64 as Int64:
            try container.encode(int64)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodableValue($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodableValue($0) })
        default:
            // Fallback to string representation
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Response Types

/// Auth status response from daemon.
struct DaemonAuthStatus: Codable {
    let authenticated: Bool
    let userId: String?
    let email: String?
    let expiresAt: String?  // RFC3339 string from daemon

    enum CodingKeys: String, CodingKey {
        case authenticated
        case userId = "user_id"
        case email
        case expiresAt = "expires_at"
    }
}

/// Session from daemon.
struct DaemonSession: Codable, Identifiable {
    let id: String
    let repositoryId: String
    let title: String
    let claudeSessionId: String?
    let status: String
    let isWorktree: Bool?
    let worktreePath: String?
    let createdAt: String  // RFC3339 string from daemon
    let lastAccessedAt: String  // RFC3339 string from daemon

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryId = "repository_id"
        case title
        case claudeSessionId = "claude_session_id"
        case status
        case isWorktree = "is_worktree"
        case worktreePath = "worktree_path"
        case createdAt = "created_at"
        case lastAccessedAt = "last_accessed_at"
    }

    /// Convert to local Session model.
    func toSession() -> Session? {
        guard let uuid = UUID(uuidString: id),
              let repoUuid = UUID(uuidString: repositoryId) else {
            return nil
        }

        // Parse the RFC3339 date strings
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let created = formatter.date(from: createdAt) ?? Date()
        let lastAccessed = formatter.date(from: lastAccessedAt) ?? Date()

        return Session(
            id: uuid,
            repositoryId: repoUuid,
            title: title,
            claudeSessionId: claudeSessionId,
            status: SessionStatus(rawValue: status) ?? .active,
            isWorktree: isWorktree ?? false,
            worktreePath: worktreePath,
            createdAt: created,
            lastAccessed: lastAccessed
        )
    }
}

/// Repository from daemon.
struct DaemonRepository: Codable, Identifiable {
    let id: String
    let name: String
    let path: String
    let isGitRepository: Bool?
    let lastAccessedAt: String  // RFC3339 string from daemon

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case isGitRepository = "is_git_repository"
        case lastAccessedAt = "last_accessed_at"
    }

    /// Convert to local Repository model.
    func toRepository() -> Repository? {
        guard let uuid = UUID(uuidString: id) else {
            return nil
        }

        // Parse the RFC3339 date string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lastAccessed = formatter.date(from: lastAccessedAt) ?? Date()

        return Repository(
            id: uuid,
            path: path,
            name: name,
            lastAccessed: lastAccessed,
            addedAt: lastAccessed,  // Daemon doesn't send created_at, use last_accessed
            isGitRepository: isGitRepository ?? true
        )
    }
}

/// File entry from daemon file listing.
struct DaemonFileEntry: Codable, Identifiable {
    let id: String
    let name: String
    let path: String
    let isDir: Bool
    let hasChildren: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case isDir = "is_dir"
        case hasChildren = "has_children"
    }

    init(name: String, path: String, isDir: Bool, hasChildren: Bool) {
        self.name = name
        self.path = path
        self.isDir = isDir
        self.hasChildren = hasChildren
        self.id = path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        isDir = try container.decode(Bool.self, forKey: .isDir)
        hasChildren = try container.decode(Bool.self, forKey: .hasChildren)
        id = path
    }
}

/// File content response from daemon.
struct DaemonFileContent: Codable {
    let content: String
    let isTruncated: Bool
    let revision: DaemonFileRevision?
    let totalLines: Int?
    let readOnlyReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case isTruncated = "is_truncated"
        case revision
        case totalLines = "total_lines"
        case readOnlyReason = "read_only_reason"
    }
}

/// Opaque file revision model returned by daemon.
struct DaemonFileRevision: Codable, Hashable {
    let token: String
    let lenBytes: Int64
    let modifiedUnixNs: Int64

    enum CodingKeys: String, CodingKey {
        case token
        case lenBytes = "len_bytes"
        case modifiedUnixNs = "modified_unix_ns"
    }
}

/// Slice read response for partial file loading.
struct DaemonFileSlice: Codable {
    let content: String
    let startLine: Int
    let endLineExclusive: Int
    let totalLines: Int
    let hasMoreBefore: Bool
    let hasMoreAfter: Bool
    let isTruncated: Bool
    let revision: DaemonFileRevision

    enum CodingKeys: String, CodingKey {
        case content
        case startLine = "start_line"
        case endLineExclusive = "end_line_exclusive"
        case totalLines = "total_lines"
        case hasMoreBefore = "has_more_before"
        case hasMoreAfter = "has_more_after"
        case isTruncated = "is_truncated"
        case revision
    }
}

/// Write operation result from daemon.
struct DaemonWriteResult: Codable {
    let revision: DaemonFileRevision
    let bytesWritten: Int64
    let totalLines: Int

    enum CodingKeys: String, CodingKey {
        case revision
        case bytesWritten = "bytes_written"
        case totalLines = "total_lines"
    }
}

/// Message from daemon.
struct DaemonMessage: Codable, Identifiable {
    let id: String
    let sessionId: String
    let content: String?       // Optional - null when decryption fails
    let sequenceNumber: Int
    let timestamp: String?     // RFC3339 string from daemon
    let isStreaming: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case content
        case sequenceNumber = "sequence_number"
        case timestamp
        case isStreaming = "is_streaming"
    }

    /// Parse the timestamp string into a Date.
    var date: Date? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp)
    }
}

/// Claude status from daemon.
struct DaemonClaudeStatus: Codable {
    let isRunning: Bool
    let sessionId: String?
    let processId: Int?

    enum CodingKeys: String, CodingKey {
        case isRunning = "is_running"
        case sessionId = "session_id"
        case processId = "process_id"
    }
}

/// Result of a git commit operation.
struct GitCommitResultResponse: Codable {
    let oid: String
    let shortOid: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case oid
        case shortOid = "short_oid"
        case summary
    }
}

/// Result of a git push operation.
struct GitPushResultResponse: Codable {
    let remote: String
    let branch: String
    let success: Bool
}

/// Git status from daemon.
struct DaemonGitStatus: Codable {
    let branch: String?
    let ahead: Int
    let behind: Int
    let staged: [DaemonGitFileChange]
    let unstaged: [DaemonGitFileChange]
    let untracked: [String]

    /// Check if the working directory is clean (no changes).
    var isClean: Bool {
        staged.isEmpty && unstaged.isEmpty && untracked.isEmpty
    }

    struct DaemonGitFileChange: Codable {
        let path: String
        let status: String
        let oldPath: String?

        enum CodingKeys: String, CodingKey {
            case path
            case status
            case oldPath = "old_path"
        }
    }
}
