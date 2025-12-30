//
//  WorkspaceModels.swift
//  rocketry-macos
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import Foundation

// MARK: - Workspace Status

enum WorkspaceStatus: String, Codable, Hashable {
    case active
    case archived
    case error
}

// MARK: - Workspace

struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let projectId: UUID?
    var worktreePath: String?
    let createdAt: Date
    var lastAccessed: Date
    var status: WorkspaceStatus

    // UI state (not persisted)
    var repositories: [Repository]
    var isExpanded: Bool

    // CodingKeys to exclude UI state from persistence
    enum CodingKeys: String, CodingKey {
        case id, name, projectId, worktreePath, createdAt, lastAccessed, status
    }

    init(
        id: UUID = UUID(),
        name: String,
        projectId: UUID? = nil,
        worktreePath: String? = nil,
        createdAt: Date = Date(),
        lastAccessed: Date = Date(),
        status: WorkspaceStatus = .active,
        repositories: [Repository] = [],
        isExpanded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.projectId = projectId
        self.worktreePath = worktreePath
        self.createdAt = createdAt
        self.lastAccessed = lastAccessed
        self.status = status
        self.repositories = repositories
        self.isExpanded = isExpanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastAccessed = try container.decode(Date.self, forKey: .lastAccessed)
        status = try container.decode(WorkspaceStatus.self, forKey: .status)

        // Initialize UI state with defaults
        repositories = []
        isExpanded = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(worktreePath, forKey: .worktreePath)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastAccessed, forKey: .lastAccessed)
        try container.encode(status, forKey: .status)
    }

    /// Check if the worktree directory exists
    var worktreeExists: Bool {
        guard let path = worktreePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Display path with ~ for home directory
    var displayPath: String? {
        worktreePath.map { ($0 as NSString).abbreviatingWithTildeInPath }
    }
}

// MARK: - Repository

struct Repository: Identifiable, Hashable {
    let id: UUID
    let name: String
    let branchName: String
    var branches: [Branch]
    var isSelected: Bool
    let lastUpdated: String
    let keyboardShortcut: String?

    init(
        id: UUID = UUID(),
        name: String,
        branchName: String = "main",
        branches: [Branch] = [],
        isSelected: Bool = false,
        lastUpdated: String = "",
        keyboardShortcut: String? = nil
    ) {
        self.id = id
        self.name = name
        self.branchName = branchName
        self.branches = branches
        self.isSelected = isSelected
        self.lastUpdated = lastUpdated
        self.keyboardShortcut = keyboardShortcut
    }
}

// MARK: - Branch

struct Branch: Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: BranchType
    let additions: Int
    let deletions: Int
    let prNumber: Int?
    let isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        type: BranchType = .branch,
        additions: Int = 0,
        deletions: Int = 0,
        prNumber: Int? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.additions = additions
        self.deletions = deletions
        self.prNumber = prNumber
        self.isArchived = isArchived
    }

    var statsText: String {
        if additions > 0 || deletions > 0 {
            return "+\(additions) -\(deletions)"
        }
        return ""
    }
}

// MARK: - Branch Type

enum BranchType: String, Hashable {
    case branch
    case pullRequest

    var iconName: String {
        switch self {
        case .branch: return "arrow.triangle.branch"
        case .pullRequest: return "arrow.triangle.pull"
        }
    }
}
