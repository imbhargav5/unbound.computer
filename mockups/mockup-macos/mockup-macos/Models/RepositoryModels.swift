//
//  RepositoryModels.swift
//  mockup-macos
//
//  Models for registered local repositories
//

import Foundation

// MARK: - Repository

struct Repository: Identifiable, Hashable {
    let id: UUID
    let path: String
    let name: String
    var lastAccessed: Date
    let addedAt: Date
    var isGitRepository: Bool

    // Settings
    var sessionsPath: String?
    var defaultBranch: String?
    var defaultRemote: String?

    init(
        id: UUID = UUID(),
        path: String,
        name: String? = nil,
        lastAccessed: Date = Date(),
        addedAt: Date = Date(),
        isGitRepository: Bool = false,
        sessionsPath: String? = nil,
        defaultBranch: String? = nil,
        defaultRemote: String? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.lastAccessed = lastAccessed
        self.addedAt = addedAt
        self.isGitRepository = isGitRepository
        self.sessionsPath = sessionsPath
        self.defaultBranch = defaultBranch
        self.defaultRemote = defaultRemote
    }

    /// Display path with ~ for home directory
    var displayPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// Check if the repository directory still exists
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Display sessions path with ~ for home directory
    var displaySessionsPath: String? {
        sessionsPath.map { ($0 as NSString).abbreviatingWithTildeInPath }
    }
}
