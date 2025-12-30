//
//  WorkspacesService.swift
//  rocketry-macos
//
//  Manages workspaces with git worktree creation
//

import Foundation

// MARK: - Workspaces Store (for JSON persistence)

struct WorkspacesStore: Codable {
    var workspaces: [Workspace]
    let version: Int

    init(workspaces: [Workspace] = [], version: Int = 1) {
        self.workspaces = workspaces
        self.version = version
    }
}

// MARK: - Workspaces Error

enum WorkspacesError: Error, LocalizedError {
    case workspaceAlreadyExists(String)
    case workspaceNotFound(UUID)
    case projectNotFound(UUID)
    case worktreeCreationFailed(String)
    case persistenceFailed(String)
    case directoryCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .workspaceAlreadyExists(let name):
            return "Workspace already exists: \(name)"
        case .workspaceNotFound(let id):
            return "Workspace not found: \(id)"
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .worktreeCreationFailed(let reason):
            return "Failed to create worktree: \(reason)"
        case .persistenceFailed(let reason):
            return "Failed to save workspaces: \(reason)"
        case .directoryCreationFailed(let reason):
            return "Failed to create directory: \(reason)"
        }
    }
}

// MARK: - Workspaces Service

@Observable
class WorkspacesService {
    private let gitService: GitService
    private let projectsService: ProjectsService

    private(set) var workspaces: [Workspace] = []

    // MARK: - Name Generation

    private let adjectives = [
        "happy", "clever", "brave", "calm", "eager",
        "gentle", "jolly", "kind", "lively", "proud",
        "quiet", "swift", "wise", "witty", "bold",
        "bright", "cool", "daring", "epic", "fancy",
        "grand", "humble", "keen", "lucky", "merry",
        "noble", "quick", "sharp", "vivid", "zen"
    ]

    private let animals = [
        "panda", "wolf", "falcon", "orca", "otter",
        "tiger", "raven", "bear", "fox", "hawk",
        "lynx", "owl", "seal", "deer", "hare",
        "eagle", "dolphin", "koala", "penguin", "jaguar",
        "phoenix", "dragon", "griffin", "unicorn", "sphinx",
        "badger", "ferret", "meerkat", "lemur", "gecko"
    ]

    /// Storage directory for app configuration
    private var appSupportURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Rocketry", isDirectory: true)
    }

    /// Path to workspaces.json
    private var storageURL: URL {
        appSupportURL.appendingPathComponent("workspaces.json")
    }

    /// Base directory for worktrees
    private var worktreesDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("unbound/worktrees", isDirectory: true)
    }

    init(gitService: GitService, projectsService: ProjectsService) {
        self.gitService = gitService
        self.projectsService = projectsService
    }

    // MARK: - Persistence

    /// Load workspaces from disk
    func load() throws {
        // Ensure app support directory exists
        try ensureAppSupportDirectoryExists()

        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            workspaces = []
            return
        }

        let data = try Data(contentsOf: storageURL)
        let store = try JSONDecoder().decode(WorkspacesStore.self, from: data)
        workspaces = store.workspaces
    }

    /// Save workspaces to disk
    func save() throws {
        try ensureAppSupportDirectoryExists()

        let store = WorkspacesStore(workspaces: workspaces)
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

    /// Ensure worktrees directory exists
    private func ensureWorktreesDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: worktreesDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: worktreesDirectory, withIntermediateDirectories: true)
            } catch {
                throw WorkspacesError.directoryCreationFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Workspace Management

    /// Generate a unique Docker-style workspace name
    func generateWorkspaceName() -> String {
        var name: String
        var attempts = 0

        repeat {
            let adjective = adjectives.randomElement()!
            let animal = animals.randomElement()!
            name = "\(adjective)-\(animal)"
            attempts += 1

            // After many attempts, add a random suffix
            if attempts > 100 {
                name = "\(name)-\(Int.random(in: 100...999))"
            }
        } while workspaces.contains(where: { $0.name == name })

        return name
    }

    /// Create a new workspace from a project
    func createWorkspace(from project: Project) async throws -> Workspace {
        // Ensure worktrees directory exists
        try ensureWorktreesDirectoryExists()

        // Generate unique name
        let name = generateWorkspaceName()

        // Create worktree path
        let worktreePath = worktreesDirectory.appendingPathComponent(name).path

        // Check if worktree path already exists
        if FileManager.default.fileExists(atPath: worktreePath) {
            throw WorkspacesError.workspaceAlreadyExists(name)
        }

        // Create git worktree
        do {
            try await gitService.createWorktree(
                source: project.path,
                destination: worktreePath,
                branch: name
            )
        } catch {
            throw WorkspacesError.worktreeCreationFailed(error.localizedDescription)
        }

        // Create workspace
        let workspace = Workspace(
            name: name,
            projectId: project.id,
            worktreePath: worktreePath,
            status: .active
        )

        workspaces.append(workspace)
        try save()

        // Update project last accessed
        try? projectsService.touch(project)

        return workspace
    }

    /// Delete a workspace (removes worktree)
    func deleteWorkspace(_ workspace: Workspace) async throws {
        guard workspaces.contains(where: { $0.id == workspace.id }) else {
            throw WorkspacesError.workspaceNotFound(workspace.id)
        }

        // Remove git worktree if it exists
        if let worktreePath = workspace.worktreePath {
            if FileManager.default.fileExists(atPath: worktreePath) {
                // Find the source project to run worktree remove
                if let projectId = workspace.projectId,
                   let project = projectsService.project(id: projectId) {
                    try? await gitService.removeWorktree(at: worktreePath)
                }

                // If worktree remove failed or no project, try direct deletion
                if FileManager.default.fileExists(atPath: worktreePath) {
                    try? FileManager.default.removeItem(atPath: worktreePath)
                }
            }
        }

        workspaces.removeAll { $0.id == workspace.id }
        try save()
    }

    /// Archive a workspace
    func archiveWorkspace(_ workspace: Workspace) throws {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            throw WorkspacesError.workspaceNotFound(workspace.id)
        }
        workspaces[index].status = .archived
        try save()
    }

    /// Unarchive a workspace
    func unarchiveWorkspace(_ workspace: Workspace) throws {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            throw WorkspacesError.workspaceNotFound(workspace.id)
        }
        workspaces[index].status = .active
        try save()
    }

    /// Update last accessed timestamp
    func touch(_ workspace: Workspace) throws {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            throw WorkspacesError.workspaceNotFound(workspace.id)
        }
        workspaces[index].lastAccessed = Date()
        try save()
    }

    /// Get workspace by ID
    func workspace(id: UUID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    /// Get active workspaces sorted by last accessed
    var activeWorkspaces: [Workspace] {
        workspaces
            .filter { $0.status == .active }
            .sorted { $0.lastAccessed > $1.lastAccessed }
    }

    /// Get archived workspaces
    var archivedWorkspaces: [Workspace] {
        workspaces
            .filter { $0.status == .archived }
            .sorted { $0.lastAccessed > $1.lastAccessed }
    }

    /// Validate workspaces (check if worktrees still exist)
    func validateWorkspaces() -> [Workspace] {
        var invalidWorkspaces: [Workspace] = []

        for i in workspaces.indices {
            if !workspaces[i].worktreeExists {
                invalidWorkspaces.append(workspaces[i])
                workspaces[i].status = .error
            }
        }

        if !invalidWorkspaces.isEmpty {
            try? save()
        }

        return invalidWorkspaces
    }

    /// Get workspaces for a specific project
    func workspaces(for project: Project) -> [Workspace] {
        workspaces.filter { $0.projectId == project.id }
    }

    /// Create a workspace placeholder without a worktree
    func createWorkspacePlaceholder(for project: Project) throws -> Workspace {
        let name = generateWorkspaceName()

        let workspace = Workspace(
            name: name,
            projectId: project.id,
            worktreePath: nil,
            status: .active
        )

        workspaces.append(workspace)
        try save()

        return workspace
    }

    /// Create worktree for an existing workspace that doesn't have one
    func createWorktreeForWorkspace(_ workspace: Workspace) async throws -> Workspace {
        guard let projectId = workspace.projectId,
              let project = projectsService.project(id: projectId) else {
            throw WorkspacesError.projectNotFound(workspace.projectId ?? UUID())
        }

        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            throw WorkspacesError.workspaceNotFound(workspace.id)
        }

        // Ensure worktrees directory exists
        try ensureWorktreesDirectoryExists()

        // Create worktree path
        let worktreePath = worktreesDirectory.appendingPathComponent(workspace.name).path

        // Check if worktree path already exists
        if FileManager.default.fileExists(atPath: worktreePath) {
            throw WorkspacesError.workspaceAlreadyExists(workspace.name)
        }

        // Create git worktree
        do {
            try await gitService.createWorktree(
                source: project.path,
                destination: worktreePath,
                branch: workspace.name
            )
        } catch {
            throw WorkspacesError.worktreeCreationFailed(error.localizedDescription)
        }

        // Update workspace with worktree path
        workspaces[index].worktreePath = worktreePath
        workspaces[index].lastAccessed = Date()

        try save()

        // Update project last accessed
        try? projectsService.touch(project)

        return workspaces[index]
    }
}
