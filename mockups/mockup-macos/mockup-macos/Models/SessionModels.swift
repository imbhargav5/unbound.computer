//
//  SessionModels.swift
//  mockup-macos
//
//  Session = Claude conversation (Agent Coding Session).
//  A session is always linked to a repository, optionally in a worktree directory.
//

import Foundation

// MARK: - Session Status

enum SessionStatus: String, Hashable {
    case active
    case archived
    case error
}

// MARK: - Session (= Claude Conversation / Agent Coding Session)

struct Session: Identifiable, Hashable {
    let id: UUID
    let repositoryId: UUID
    var title: String
    var claudeSessionId: String?
    var status: SessionStatus
    // Worktree columns
    var isWorktree: Bool
    var worktreePath: String?
    let createdAt: Date
    var lastAccessed: Date

    init(
        id: UUID = UUID(),
        repositoryId: UUID,
        title: String = "New conversation",
        claudeSessionId: String? = nil,
        status: SessionStatus = .active,
        isWorktree: Bool = false,
        worktreePath: String? = nil,
        createdAt: Date = Date(),
        lastAccessed: Date = Date()
    ) {
        self.id = id
        self.repositoryId = repositoryId
        self.title = title
        self.claudeSessionId = claudeSessionId
        self.status = status
        self.isWorktree = isWorktree
        self.worktreePath = worktreePath
        self.createdAt = createdAt
        self.lastAccessed = lastAccessed
    }

    /// Display title - uses provided title or default
    var displayTitle: String {
        title.isEmpty ? "New conversation" : title
    }

    /// Check if the worktree directory still exists
    var worktreeExists: Bool {
        guard let path = worktreePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Working directory path (worktree path if worktree, else nil - caller should use repo path)
    var workingDirectory: String? {
        worktreePath
    }
}

// MARK: - Agent Status

enum AgentStatus: String, Hashable {
    case idle
    case thinking
    case toolRunning = "tool_running"
    case waitingInput = "waiting_input"
    case error
}

// MARK: - Session State (Runtime state for a session)

struct SessionState: Identifiable, Hashable {
    var id: UUID { sessionId }
    let sessionId: UUID
    var agentStatus: AgentStatus
    var queuedCommands: [QueuedCommand]
    var diffSummary: [DiffEntry]

    init(
        sessionId: UUID,
        agentStatus: AgentStatus = .idle,
        queuedCommands: [QueuedCommand] = [],
        diffSummary: [DiffEntry] = []
    ) {
        self.sessionId = sessionId
        self.agentStatus = agentStatus
        self.queuedCommands = queuedCommands
        self.diffSummary = diffSummary
    }

    /// Total additions across all changed files
    var totalAdditions: Int {
        diffSummary.reduce(0) { $0 + $1.additions }
    }

    /// Total deletions across all changed files
    var totalDeletions: Int {
        diffSummary.reduce(0) { $0 + $1.deletions }
    }

    /// Number of changed files
    var changedFilesCount: Int {
        diffSummary.count
    }
}

// MARK: - Queued Command

struct QueuedCommand: Identifiable, Hashable {
    let id: UUID
    let type: CommandType
    let command: String
    let description: String?

    init(
        id: UUID = UUID(),
        type: CommandType,
        command: String,
        description: String? = nil
    ) {
        self.id = id
        self.type = type
        self.command = command
        self.description = description
    }
}

enum CommandType: String, Hashable {
    case bash
    case edit
    case write
    case read
    case other
}

// MARK: - Diff Entry

struct DiffEntry: Identifiable, Hashable {
    let id: UUID
    let filepath: String
    let filename: String
    let status: FileStatus
    let additions: Int
    let deletions: Int
    let oldPath: String?

    init(
        id: UUID = UUID(),
        filepath: String,
        filename: String? = nil,
        status: FileStatus,
        additions: Int = 0,
        deletions: Int = 0,
        oldPath: String? = nil
    ) {
        self.id = id
        self.filepath = filepath
        self.filename = filename ?? URL(fileURLWithPath: filepath).lastPathComponent
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.oldPath = oldPath
    }

    /// Stats display text
    var statsText: String {
        if additions > 0 || deletions > 0 {
            return "+\(additions) -\(deletions)"
        }
        return ""
    }
}

/// Git file status with standard visual indicators.
/// Design principles:
/// - Git-standard letter codes (M, A, D, R, ?)
/// - Semantic colors (Green=Added, Yellow=Modified, Red=Deleted, Gray=Untracked)
/// - No abstract icons like pencil; use explicit status symbols
enum FileStatus: String, Hashable {
    case modified
    case added
    case deleted
    case renamed
    case untracked

    /// Git-standard single-letter indicator
    var indicator: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "?"
        }
    }

    /// SF Symbol icon - uses semantic Git metaphors
    var iconName: String {
        switch self {
        case .modified: return "circle.fill"    // Filled dot for modified
        case .added: return "plus"              // Standard Git + for added
        case .deleted: return "minus"           // Standard Git - for deleted
        case .renamed: return "arrow.right"     // Movement indicator
        case .untracked: return "questionmark"  // Unknown/untracked
        }
    }

    /// Display name for accessibility and labels
    var displayName: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .untracked: return "Untracked"
        }
    }

    /// Color name for reference (actual Color values in view)
    var color: String {
        switch self {
        case .modified: return "yellow"
        case .added: return "green"
        case .deleted: return "red"
        case .renamed: return "blue"
        case .untracked: return "gray"
        }
    }
}

// MARK: - Session Location Type

enum SessionLocationType: String, Hashable {
    case mainDirectory = "main"
    case newWorktree = "worktree"
}
