//
//  ProjectsService.swift
//  unbound-macos
//
//  Manages registered projects with persistence
//

import Foundation
import AppKit

// MARK: - Projects Error

enum ProjectsError: Error, LocalizedError {
    case projectAlreadyExists(String)
    case projectNotFound(UUID)
    case notAGitRepository(String)
    case persistenceFailed(String)
    case folderCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectAlreadyExists(let path):
            return "Project already registered: \(path)"
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        case .persistenceFailed(let reason):
            return "Failed to save projects: \(reason)"
        case .folderCreationFailed(let reason):
            return "Failed to create folder: \(reason)"
        }
    }
}

// MARK: - Projects Service

@Observable
class ProjectsService {
    private let gitService: GitService

    private(set) var projects: [Project] = []

    /// Storage directory for app configuration
    private var appSupportURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Unbound", isDirectory: true)
    }

    /// Path to projects.json
    private var storageURL: URL {
        appSupportURL.appendingPathComponent("projects.json")
    }

    init(gitService: GitService) {
        self.gitService = gitService
    }

    // MARK: - Persistence

    /// Load projects from disk
    func load() throws {
        // Ensure app support directory exists
        try ensureAppSupportDirectoryExists()

        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            projects = []
            return
        }

        let data = try Data(contentsOf: storageURL)
        let store = try JSONDecoder().decode(ProjectsStore.self, from: data)
        projects = store.projects
    }

    /// Save projects to disk
    func save() throws {
        try ensureAppSupportDirectoryExists()

        let store = ProjectsStore(projects: projects)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: storageURL, options: .atomic)
    }

    /// Ensure app support directory exists
    private func ensureAppSupportDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: appSupportURL.path) {
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Project Management

    /// Add a project via folder picker
    func addProjectWithPicker() async throws -> Project? {
        // Show folder picker on main thread
        let selectedPath = await MainActor.run { () -> String? in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select a project folder"
            panel.prompt = "Add Project"

            let response = panel.runModal()
            guard response == .OK, let url = panel.url else {
                return nil
            }
            return url.path
        }

        guard let path = selectedPath else {
            return nil
        }

        return try await addProject(at: path)
    }

    /// Add a project at the specified path
    func addProject(at path: String) async throws -> Project {
        // Check if already registered
        if projects.contains(where: { $0.path == path }) {
            throw ProjectsError.projectAlreadyExists(path)
        }

        // Check if it's a git repository
        let isGit = await gitService.isGitRepository(at: path)
        if !isGit {
            throw ProjectsError.notAGitRepository(path)
        }

        // Create .unbound folder in project
        try await createUnboundFolder(in: path)

        // Create project
        let project = Project(
            path: path,
            isGitRepository: isGit
        )

        projects.append(project)
        try save()

        return project
    }

    /// Create .unbound folder in project for future per-project config
    private func createUnboundFolder(in projectPath: String) async throws {
        let unboundPath = (projectPath as NSString).appendingPathComponent(".unbound")

        if !FileManager.default.fileExists(atPath: unboundPath) {
            do {
                try FileManager.default.createDirectory(
                    atPath: unboundPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                // Create a .gitkeep to ensure folder is tracked if needed
                let gitkeepPath = (unboundPath as NSString).appendingPathComponent(".gitkeep")
                FileManager.default.createFile(atPath: gitkeepPath, contents: nil)
            } catch {
                throw ProjectsError.folderCreationFailed(error.localizedDescription)
            }
        }
    }

    /// Remove a project
    func removeProject(_ project: Project) throws {
        projects.removeAll { $0.id == project.id }
        try save()
    }

    /// Remove project by ID
    func removeProject(id: UUID) throws {
        guard projects.contains(where: { $0.id == id }) else {
            throw ProjectsError.projectNotFound(id)
        }
        projects.removeAll { $0.id == id }
        try save()
    }

    /// Update last accessed timestamp
    func touch(_ project: Project) throws {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            throw ProjectsError.projectNotFound(project.id)
        }
        projects[index].lastAccessed = Date()
        try save()
    }

    /// Validate that all projects still exist
    func validateProjects() -> [Project] {
        let invalidProjects = projects.filter { !$0.exists }

        if !invalidProjects.isEmpty {
            projects.removeAll { !$0.exists }
            try? save()
        }

        return invalidProjects
    }

    /// Get project by ID
    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    /// Get projects sorted by last accessed
    var recentProjects: [Project] {
        projects.sorted { $0.lastAccessed > $1.lastAccessed }
    }
}
