//
//  RepositoryModels.swift
//  unbound-macos
//
//  Models for registered local repositories
//
//  Architecture: Repository is a logical container with zero execution state.
//  All work happens in Sessions (worktrees). Settings sync to Supabase.
//

import Foundation

// MARK: - Repository

struct Repository: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    let name: String
    var lastAccessed: Date
    let addedAt: Date
    var isGitRepository: Bool

    // Settings (synced to Supabase)
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

// MARK: - Repositories Store (for JSON persistence)

struct RepositoriesStore: Codable {
    var repositories: [Repository]
    let version: Int

    init(repositories: [Repository] = [], version: Int = 2) {
        self.repositories = repositories
        self.version = version
    }
}

// MARK: - Migration from Legacy ProjectsStore

extension RepositoriesStore {
    /// Migrate from legacy ProjectsStore format
    init(migratingFrom legacyData: Data) throws {
        let decoder = JSONDecoder()

        // Try to decode as legacy ProjectsStore
        struct LegacyProjectsStore: Codable {
            var projects: [LegacyProject]
            let version: Int
        }

        struct LegacyProject: Codable {
            let id: UUID
            let path: String
            let name: String
            var lastAccessed: Date
            let addedAt: Date
            var isGitRepository: Bool
        }

        let legacy = try decoder.decode(LegacyProjectsStore.self, from: legacyData)

        // Convert to repositories
        self.repositories = legacy.projects.map { project in
            Repository(
                id: project.id,
                path: project.path,
                name: project.name,
                lastAccessed: project.lastAccessed,
                addedAt: project.addedAt,
                isGitRepository: project.isGitRepository
            )
        }
        self.version = 2
    }
}
