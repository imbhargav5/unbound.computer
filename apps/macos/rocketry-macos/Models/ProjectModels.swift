//
//  ProjectModels.swift
//  rocketry-macos
//
//  Models for registered local projects
//

import Foundation

// MARK: - Project

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    let name: String
    var lastAccessed: Date
    let addedAt: Date
    var isGitRepository: Bool

    init(
        id: UUID = UUID(),
        path: String,
        name: String? = nil,
        lastAccessed: Date = Date(),
        addedAt: Date = Date(),
        isGitRepository: Bool = false
    ) {
        self.id = id
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.lastAccessed = lastAccessed
        self.addedAt = addedAt
        self.isGitRepository = isGitRepository
    }

    /// Display path with ~ for home directory
    var displayPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// Check if the project directory still exists
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - Projects Store (for JSON persistence)

struct ProjectsStore: Codable {
    var projects: [Project]
    let version: Int

    init(projects: [Project] = [], version: Int = 1) {
        self.projects = projects
        self.version = version
    }
}
