//
//  AppState.swift
//  unbound-macos
//
//  Main application state for the local-only macOS client.
//

import Logging
import OpenTelemetryApi
import SwiftUI

private let logger = Logger(label: "app.state")

// MARK: - Theme Mode

enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Dependency Check State

enum DependencyCheckStatus: Equatable {
    case unchecked
    case checking
    case satisfied
    case claudeMissing
}

// MARK: - Daemon Connection State

enum DaemonConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}

// MARK: - App State

@MainActor
@Observable
class AppState {
    let daemonClient = DaemonClient.shared
    let sessionStateManager = SessionStateManager()

    private(set) var daemonConnectionState: DaemonConnectionState = .disconnected
    private(set) var daemonError: String?

    var isDaemonConnected: Bool {
        daemonConnectionState.isConnected
    }

    private(set) var dependencyStatus: DependencyCheckStatus = .unchecked
    private(set) var isGhInstalled: Bool?

    var dependenciesSatisfied: Bool {
        dependencyStatus == .satisfied
    }

    var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode")
        }
    }

    let localSettings = LocalSettings.shared

    var showSettings: Bool = false
    var showCommandPalette: Bool = false
    var selectedSessionId: UUID?
    var selectedRepositoryId: UUID?

    private(set) var repositories: [Repository] = []
    private(set) var sessions: [UUID: [Session]] = [:]

    private(set) var isLoadingRepositories: Bool = false
    private(set) var isLoadingSessions: Bool = false

    init() {
        logger.info("AppState.init started")

        if let savedTheme = UserDefaults.standard.string(forKey: "themeMode"),
           let theme = ThemeMode(rawValue: savedTheme) {
            self.themeMode = theme
        } else {
            self.themeMode = .system
        }

        logger.info("AppState.init completed")
    }

    // MARK: - Daemon Connection

    func connectToDaemon() async {
        logger.info("Connecting to daemon...")
        daemonConnectionState = .connecting
        daemonError = nil

        do {
            try await DaemonLauncher.ensureDaemonRunning()
            try await daemonClient.connect()

            daemonConnectionState = .connected
            logger.info("Connected to daemon")

            await checkDependencies()
            if dependenciesSatisfied {
                await loadDataAsync()
            }
        } catch {
            logger.error("Failed to connect to daemon: \(error)")
            daemonConnectionState = .failed(error.localizedDescription)
            daemonError = error.localizedDescription
        }
    }

    func disconnectFromDaemon() {
        logger.info("Disconnecting from daemon")
        sessionStateManager.deactivateAll()
        daemonClient.disconnect()
        daemonConnectionState = .disconnected
        clearCachedData()
    }

    func retryDaemonConnection() async {
        daemonClient.resetReconnectState()
        await connectToDaemon()
    }

    // MARK: - Dependency Checking

    func checkDependencies() async {
        await TracingService.withUserIntentRootIfNeeded(
            name: "system.check_dependencies",
            attributes: userIntentAttributes()
        ) { _ in
            dependencyStatus = .checking
            do {
                let result = try await withThrowingTaskGroup(of: DaemonDependencyStatus.self) { group in
                    group.addTask {
                        try await self.daemonClient.checkDependencies()
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(8))
                        throw DaemonError.requestTimeout
                    }

                    let firstResult = try await group.next()!
                    group.cancelAll()
                    return firstResult
                }

                isGhInstalled = result.gh.installed
                if result.claude.installed {
                    dependencyStatus = .satisfied
                    logger.info("Dependency check passed: claude=\(result.claude.path ?? "?"), gh=\(result.gh.installed)")
                } else {
                    dependencyStatus = .claudeMissing
                    logger.warning("Claude Code CLI not found")
                }
            } catch {
                logger.error("Dependency check failed: \(error)")
                dependencyStatus = .claudeMissing
            }
        }
    }

    func recheckDependencies() async {
        dependencyStatus = .unchecked
        await checkDependencies()
        if dependenciesSatisfied {
            await loadDataAsync()
        }
    }

    // MARK: - Data Loading

    func loadDataAsync() async {
        logger.info("Loading data from daemon...")

        await refreshRepositories()
        logger.info("Repositories loaded: \(repositories.count)")

        await withTaskGroup(of: Void.self) { group in
            for repo in repositories {
                group.addTask {
                    await self.refreshSessions(for: repo.id)
                }
            }
        }

        let totalSessions = sessions.values.reduce(0) { $0 + $1.count }
        logger.info("Data loaded: \(repositories.count) repositories, \(totalSessions) total sessions")
    }

    func refreshRepositories() async {
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }

        do {
            repositories = try await daemonClient.getRepositories()
            logger.debug("Loaded \(repositories.count) repositories")
        } catch {
            logger.error("Failed to load repositories: \(error)")
        }
    }

    func refreshSessions(for repositoryId: UUID) async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }

        do {
            let repoSessions = try await daemonClient.getSessions(repositoryId: repositoryId)
            sessions[repositoryId] = repoSessions
            logger.info("Loaded \(repoSessions.count) sessions for repository \(repositoryId)")
        } catch {
            logger.error("Failed to load sessions for repository \(repositoryId): \(error)")
            sessions[repositoryId] = []
        }
    }

    func sessionsForRepository(_ repositoryId: UUID) -> [Session] {
        (sessions[repositoryId] ?? []).sorted(by: Session.isMoreRecent(_:than:))
    }

    func sessionsForAgent(_ agentId: String) -> [Session] {
        sessions.values
            .flatMap { $0 }
            .filter { $0.agentId == agentId }
            .sorted(by: Session.isMoreRecent(_:than:))
    }

    private func clearCachedData() {
        repositories = []
        sessions = [:]
        selectedSessionId = nil
        selectedRepositoryId = nil
    }

    private func userIntentAttributes(
        sessionId: UUID? = nil,
        repositoryId: UUID? = nil,
        extra: [String: AttributeValue] = [:]
    ) -> [String: AttributeValue] {
        var attributes = extra

        if let sessionId {
            attributes["session.id"] = .string(sessionId.uuidString.lowercased())
        }
        if let repositoryId {
            let value = repositoryId.uuidString.lowercased()
            attributes["repository.id"] = .string(value)
            attributes["workspace.id"] = .string(value)
        }

        return attributes
    }

    // MARK: - Repository Management

    func addRepository(path: String) async throws -> Repository {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "repository.add",
            attributes: userIntentAttributes(
                extra: ["repository.path_hash": .string(TracingService.hashIdentifier(path) ?? "")]
            )
        ) { scope in
            let name = URL(fileURLWithPath: path).lastPathComponent
            let daemonRepo = try await daemonClient.addRepository(name: name, path: path)
            guard let repo = daemonRepo.toRepository() else {
                throw DaemonError.decodingFailed("Invalid repository data")
            }
            repositories.append(repo)
            scope?.setAttributes(userIntentAttributes(repositoryId: repo.id))
            return repo
        }
    }

    func removeRepository(_ repositoryId: UUID) async throws {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "repository.remove",
            attributes: userIntentAttributes(repositoryId: repositoryId)
        ) { _ in
            try await daemonClient.removeRepository(repositoryId: repositoryId.uuidString)
            repositories.removeAll { $0.id == repositoryId }
            sessions.removeValue(forKey: repositoryId)

            if selectedRepositoryId == repositoryId {
                selectedRepositoryId = nil
                selectedSessionId = nil
            }
        }
    }

    func getRepositorySettings(_ repositoryId: UUID) async throws -> RepositorySettings {
        let daemonSettings = try await daemonClient.getRepositorySettings(
            repositoryId: repositoryId.uuidString
        )
        guard let settings = daemonSettings.toRepositorySettings() else {
            throw DaemonError.decodingFailed("Invalid repository settings data")
        }
        mergeRepository(settings.repository)
        return settings
    }

    func updateRepositorySettings(
        _ repositoryId: UUID,
        sessionsPath: String?,
        defaultBranch: String?,
        defaultRemote: String?,
        worktreeRootDir: String,
        worktreeDefaultBaseBranch: String?,
        preCreateCommand: String?,
        preCreateTimeoutSeconds: Int,
        postCreateCommand: String?,
        postCreateTimeoutSeconds: Int
    ) async throws -> RepositorySettings {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "repository.settings.update",
            attributes: userIntentAttributes(repositoryId: repositoryId)
        ) { _ in
            let daemonSettings = try await daemonClient.updateRepositorySettings(
                repositoryId: repositoryId.uuidString,
                sessionsPath: sessionsPath,
                defaultBranch: defaultBranch,
                defaultRemote: defaultRemote,
                worktreeRootDir: worktreeRootDir,
                worktreeDefaultBaseBranch: worktreeDefaultBaseBranch,
                preCreateCommand: preCreateCommand,
                preCreateTimeoutSeconds: preCreateTimeoutSeconds,
                postCreateCommand: postCreateCommand,
                postCreateTimeoutSeconds: postCreateTimeoutSeconds
            )
            guard let settings = daemonSettings.toRepositorySettings() else {
                throw DaemonError.decodingFailed("Invalid repository settings data")
            }
            mergeRepository(settings.repository)
            return settings
        }
    }

    // MARK: - Session Management

    func createSession(
        repositoryId: UUID,
        title: String? = nil,
        locationType: SessionLocationType = .mainDirectory,
        agentId: String? = nil,
        agentName: String? = nil,
        issueId: String? = nil,
        issueTitle: String? = nil,
        issueURL: String? = nil
    ) async throws -> Session {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "session.create",
            attributes: userIntentAttributes(repositoryId: repositoryId)
        ) { scope in
            let isWorktree = locationType == .worktree
            let repositoryDefaults = repositories.first(where: { $0.id == repositoryId })
            let daemonSession = try await daemonClient.createSession(
                repositoryId: repositoryId.uuidString,
                title: title,
                isWorktree: isWorktree,
                baseBranch: isWorktree ? repositoryDefaults?.defaultBranch : nil,
                agentId: agentId,
                agentName: agentName,
                issueId: issueId,
                issueTitle: issueTitle,
                issueURL: issueURL
            )
            guard let session = daemonSession.toSession() else {
                throw DaemonError.decodingFailed("Invalid session data")
            }

            if sessions[repositoryId] != nil {
                sessions[repositoryId]?.append(session)
            } else {
                sessions[repositoryId] = [session]
            }

            scope?.setAttributes(userIntentAttributes(sessionId: session.id, repositoryId: repositoryId))
            return session
        }
    }

    func deleteSession(_ sessionId: UUID, repositoryId: UUID) async throws {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "session.delete",
            attributes: userIntentAttributes(sessionId: sessionId, repositoryId: repositoryId)
        ) { _ in
            try await daemonClient.deleteSession(sessionId: sessionId.uuidString)

            sessionStateManager.remove(sessionId: sessionId)
            sessions[repositoryId]?.removeAll { $0.id == sessionId }

            if selectedSessionId == sessionId {
                selectedSessionId = nil
            }
        }
    }

    func renameSession(_ sessionId: UUID, repositoryId: UUID, title: String) async throws -> Session {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "session.rename",
            attributes: userIntentAttributes(sessionId: sessionId, repositoryId: repositoryId)
        ) { scope in
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle.isEmpty {
                throw DaemonError.serverError(
                    code: DaemonErrorCode.invalidParams,
                    message: "title must not be empty"
                )
            }

            if let existing = session(id: sessionId), existing.title == trimmedTitle {
                scope?.setAttribute("result", value: .string("no_changes"))
                return existing
            }

            let daemonSession = try await daemonClient.updateSessionTitle(
                sessionId: sessionId.uuidString,
                title: trimmedTitle
            )
            guard let session = daemonSession.toSession() else {
                throw DaemonError.decodingFailed("Invalid session data")
            }

            if let index = sessions[repositoryId]?.firstIndex(where: { $0.id == sessionId }) {
                sessions[repositoryId]?[index] = session
            } else if sessions[repositoryId] != nil {
                sessions[repositoryId]?.append(session)
            } else {
                sessions[repositoryId] = [session]
            }

            return session
        }
    }

    func session(id: UUID) -> Session? {
        for (_, repoSessions) in sessions {
            if let session = repoSessions.first(where: { $0.id == id }) {
                return session
            }
        }
        return nil
    }

    private func mergeRepository(_ repository: Repository) {
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[index] = repository
            return
        }
        repositories.append(repository)
    }

    // MARK: - Selection

    func selectSession(_ sessionId: UUID?, source: UserIntentSource = .unknown) {
        guard let sessionId else {
            selectedSessionId = nil
            return
        }

        let repositoryId = sessions.first(where: { _, repoSessions in
            repoSessions.contains(where: { $0.id == sessionId })
        })?.key

        let sessionOpenScope = sessionStateManager.beginSessionOpen(
            sessionId: sessionId,
            repositoryId: repositoryId,
            source: source,
            userIdHash: nil,
            workspaceId: repositoryId?.uuidString.lowercased()
        )

        TracingService.withChildSpan(
            name: "session.select",
            sessionId: sessionId.uuidString.lowercased(),
            parentScope: sessionOpenScope,
            attributes: userIntentAttributes(sessionId: sessionId, repositoryId: repositoryId)
        ) { _ in
            selectedSessionId = sessionId
            if let repositoryId {
                selectedRepositoryId = repositoryId
            }
        }
    }

    func selectRepository(_ repositoryId: UUID?) {
        selectedRepositoryId = repositoryId

        if let repoId = repositoryId,
           let sessionId = selectedSessionId,
           !(sessions[repoId]?.contains(where: { $0.id == sessionId }) ?? false) {
            selectedSessionId = nil
        }
    }

    #if DEBUG
    func configureForPreview(
        repositories: [Repository] = [],
        sessions: [UUID: [Session]] = [:],
        selectedRepositoryId: UUID? = nil,
        selectedSessionId: UUID? = nil,
        dependencyStatus: DependencyCheckStatus = .satisfied,
        isGhInstalled: Bool? = true
    ) {
        self.daemonConnectionState = .connected
        self.repositories = repositories
        self.sessions = sessions
        self.selectedRepositoryId = selectedRepositoryId
        self.selectedSessionId = selectedSessionId
        self.dependencyStatus = dependencyStatus
        self.isGhInstalled = isGhInstalled
    }
    #endif
}

// MARK: - Convenience Accessors

extension AppState {
    var selectedRepository: Repository? {
        guard let id = selectedRepositoryId else { return nil }
        return repositories.first { $0.id == id }
    }

    var selectedSession: Session? {
        guard let id = selectedSessionId else { return nil }
        return session(id: id)
    }

    var selectedRepositorySessions: [Session] {
        guard let id = selectedRepositoryId else { return [] }
        return sessionsForRepository(id)
    }
}
