//
//  AppState.swift
//  unbound-macos
//
//  Main application state - thin client that delegates to daemon.
//  All business logic (auth, sessions, Claude, sync) is handled by the daemon.
//  This class manages UI state and caches data from the daemon.
//

import SwiftUI
import Logging
import OpenTelemetryApi

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
    // MARK: - Daemon Client

    let daemonClient = DaemonClient.shared

    // MARK: - Session State Manager

    let sessionStateManager = SessionStateManager()
    let sessionRuntimeStatusService = SessionRuntimeStatusService.shared

    // MARK: - Daemon Connection State

    private(set) var daemonConnectionState: DaemonConnectionState = .disconnected
    private(set) var daemonError: String?

    var isDaemonConnected: Bool {
        daemonConnectionState.isConnected
    }

    // MARK: - Authentication State (from daemon)

    private(set) var isAuthenticated: Bool = false
    private(set) var hasStoredSession: Bool = false
    private(set) var authState: DaemonAuthState?
    private(set) var currentUserId: String?
    private(set) var currentUserEmail: String?
    private var authValidationRefreshTask: Task<Void, Never>?

    var isAuthValidationPending: Bool {
        hasStoredSession && !isAuthenticated && (authState?.isValidationInFlight ?? false)
    }

    // MARK: - Dependency Check State

    private(set) var dependencyStatus: DependencyCheckStatus = .unchecked
    private(set) var isGhInstalled: Bool?

    var dependenciesSatisfied: Bool {
        dependencyStatus == .satisfied
    }

    // MARK: - UI State

    var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode")
        }
    }

    /// Local settings for font size and other UI preferences
    let localSettings = LocalSettings.shared

    var showSettings: Bool = false
    var showCommandPalette: Bool = false
    var selectedSessionId: UUID?
    var selectedRepositoryId: UUID?

    // MARK: - Cached Data (refreshed from daemon)

    private(set) var repositories: [Repository] = []
    private(set) var sessions: [UUID: [Session]] = [:]  // keyed by repository ID

    // MARK: - Loading States

    private(set) var isLoadingRepositories: Bool = false
    private(set) var isLoadingSessions: Bool = false

    // MARK: - Initialization

    init() {
        logger.info("AppState.init started")

        // Load theme from UserDefaults
        if let savedTheme = UserDefaults.standard.string(forKey: "themeMode"),
           let theme = ThemeMode(rawValue: savedTheme) {
            self.themeMode = theme
        } else {
            self.themeMode = .system
        }

        logger.info("AppState.init completed")
    }

    // MARK: - Daemon Connection

    /// Initialize connection to daemon.
    /// Call this on app startup.
    func connectToDaemon() async {
        logger.info("Connecting to daemon...")
        daemonConnectionState = .connecting
        daemonError = nil

        do {
            // Ensure daemon is running (start if needed)
            try await DaemonLauncher.ensureDaemonRunning()

            // Connect to daemon
            try await daemonClient.connect()

            daemonConnectionState = .connected
            logger.info("Connected to daemon")

            // Refresh auth status
            await refreshAuthStatus()

            // If authenticated, check dependencies then load data
            if isAuthenticated {
                await checkDependencies()
                if dependenciesSatisfied {
                    await loadDataAsync()
                }
            }
        } catch {
            logger.error("Failed to connect to daemon: \(error)")
            daemonConnectionState = .failed(error.localizedDescription)
            daemonError = error.localizedDescription
        }
    }

    /// Disconnect from daemon.
    func disconnectFromDaemon() {
        logger.info("Disconnecting from daemon")
        authValidationRefreshTask?.cancel()
        authValidationRefreshTask = nil
        sessionStateManager.deactivateAll()
        sessionRuntimeStatusService.stop()
        daemonClient.disconnect()
        daemonConnectionState = .disconnected
        clearCachedData()
    }

    /// Retry daemon connection.
    func retryDaemonConnection() async {
        daemonClient.resetReconnectState()
        await connectToDaemon()
    }

    // MARK: - Authentication

    /// Refresh authentication status from daemon.
    func refreshAuthStatus() async {
        await refreshAuthStatus(startValidationMonitor: true)
    }

    private func refreshAuthStatus(startValidationMonitor: Bool) async {
        do {
            let status = try await daemonClient.getAuthStatus()
            isAuthenticated = status.effectiveSessionValid
            hasStoredSession = status.effectiveHasStoredSession
            authState = status.state
            currentUserId = status.userId
            currentUserEmail = status.email
            logger.info(
                "Auth status: authenticated=\(status.effectiveSessionValid), hasStoredSession=\(status.effectiveHasStoredSession), state=\(status.state?.rawValue ?? "nil"), email=\(status.email ?? "nil")"
            )
        } catch {
            logger.error("Failed to get auth status: \(error)")
            isAuthenticated = false
            hasStoredSession = false
            authState = nil
            currentUserId = nil
            currentUserEmail = nil
        }

        await updateRuntimeStatusSubscription()

        if startValidationMonitor {
            scheduleAuthValidationRefreshIfNeeded()
        }
    }

    private func scheduleAuthValidationRefreshIfNeeded() {
        guard isAuthValidationPending else {
            authValidationRefreshTask?.cancel()
            authValidationRefreshTask = nil
            return
        }

        guard authValidationRefreshTask == nil else { return }

        authValidationRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.authValidationRefreshTask = nil }

            let deadline = Date().addingTimeInterval(45)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }

                await self.refreshAuthStatus(startValidationMonitor: false)
                guard !self.isAuthValidationPending else { continue }

                if self.isAuthenticated {
                    await self.checkDependencies()
                    if self.dependenciesSatisfied {
                        await self.loadDataAsync()
                    }
                }
                return
            }

            logger.warning("Timed out waiting for deferred auth validation to settle")
        }
    }

    /// Login via daemon with email and password.
    func loginWithPassword(email: String, password: String) async throws {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "auth.login.start",
            attributes: userIntentAttributes()
        ) { _ in
            try await daemonClient.loginWithPassword(email: email, password: password)
            await refreshAuthStatus()

            if isAuthenticated {
                await checkDependencies()
                if dependenciesSatisfied {
                    await loadDataAsync()
                }
            }
        }
    }

    /// Login via daemon with OAuth provider.
    /// - Parameters:
    ///   - provider: OAuth provider ("github", "google") or "magic_link" for passwordless.
    ///   - email: Email address (required for magic_link, optional for OAuth).
    func loginWithProvider(_ provider: String, email: String? = nil) async throws {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "auth.login.start",
            attributes: userIntentAttributes(
                extra: ["auth.provider": .string(provider)]
            )
        ) { _ in
            try await daemonClient.loginWithProvider(provider, email: email)
            await refreshAuthStatus()

            if isAuthenticated {
                await checkDependencies()
                if dependenciesSatisfied {
                    await loadDataAsync()
                }
            }
        }
    }

    /// Logout via daemon.
    func logout() async throws {
        try await TracingService.withUserIntentRootIfNeeded(
            name: "auth.logout",
            attributes: userIntentAttributes()
        ) { _ in
            try await daemonClient.logout()
            isAuthenticated = false
            hasStoredSession = false
            authState = .notLoggedIn
            currentUserId = nil
            currentUserEmail = nil
            dependencyStatus = .unchecked
            isGhInstalled = nil
            sessionRuntimeStatusService.stop()
            clearCachedData()
        }
    }

    private func updateRuntimeStatusSubscription() async {
        guard isAuthenticated, daemonConnectionState.isConnected, let userId = currentUserId else {
            sessionRuntimeStatusService.stop()
            return
        }

        await sessionRuntimeStatusService.start(userId: userId)
    }

    // MARK: - Dependency Checking

    /// Check system dependencies via the daemon.
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

    /// Reset and re-check dependencies.
    /// If the check passes, loads workspace data.
    func recheckDependencies() async {
        dependencyStatus = .unchecked
        await checkDependencies()
        if dependenciesSatisfied {
            await loadDataAsync()
        }
    }

    // MARK: - Data Loading

    /// Load all data from daemon.
    func loadDataAsync() async {
        logger.info("Loading data from daemon...")

        // Load repositories first
        await refreshRepositories()
        logger.info("Repositories loaded: \(repositories.count)")

        // Load sessions for all repositories in parallel
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

    /// Refresh repositories from daemon.
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

    /// Refresh sessions for a repository.
    func refreshSessions(for repositoryId: UUID) async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }

        do {
            let repoSessions = try await daemonClient.getSessions(repositoryId: repositoryId)
            sessions[repositoryId] = repoSessions
            logger.info("Loaded \(repoSessions.count) sessions for repository \(repositoryId)")
            for session in repoSessions {
                logger.debug("  - Session: \(session.id) '\(session.title)' status=\(session.status)")
            }
        } catch {
            logger.error("Failed to load sessions for repository \(repositoryId): \(error)")
            sessions[repositoryId] = []
        }
    }

    /// Get sessions for a repository (cached).
    func sessionsForRepository(_ repositoryId: UUID) -> [Session] {
        (sessions[repositoryId] ?? []).sorted(by: Session.isMoreRecent(_:than:))
    }

    /// Clear all cached data.
    private func clearCachedData() {
        repositories = []
        sessions = [:]
        selectedSessionId = nil
        selectedRepositoryId = nil
    }

    private var currentUserIdHash: String? {
        TracingService.hashIdentifier(currentUserId)
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
        if let currentUserIdHash {
            attributes["user.id_hash"] = .string(currentUserIdHash)
        }

        return attributes
    }

    // MARK: - Repository Management

    /// Add a repository.
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

    /// Remove a repository.
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

    /// Get repository settings (DB defaults + repo-local hook configuration).
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

    /// Update repository settings and merge the updated repository into cache.
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

    /// Create a new session.
    /// - Parameters:
    ///   - repositoryId: The repository ID
    ///   - title: Optional session title
    ///   - locationType: Where to create the session (main directory or worktree)
    func createSession(
        repositoryId: UUID,
        title: String? = nil,
        locationType: SessionLocationType = .mainDirectory
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
                baseBranch: isWorktree ? repositoryDefaults?.defaultBranch : nil
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

    /// Delete a session.
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

    /// Rename a session.
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

    /// Get a session by ID (from cache).
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

    /// Select a session and its repository.
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
            userIdHash: currentUserIdHash,
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

    /// Select a repository.
    func selectRepository(_ repositoryId: UUID?) {
        selectedRepositoryId = repositoryId

        // Clear session selection if it's not in this repository
        if let repoId = repositoryId,
           let sessionId = selectedSessionId,
           !(sessions[repoId]?.contains(where: { $0.id == sessionId }) ?? false) {
            selectedSessionId = nil
        }
    }

    // MARK: - Preview Support

    #if DEBUG
    /// Configure this AppState with fake data for Xcode Canvas previews.
    /// Bypasses daemon connection and authentication entirely.
    func configureForPreview(
        repositories: [Repository] = [],
        sessions: [UUID: [Session]] = [:],
        selectedRepositoryId: UUID? = nil,
        selectedSessionId: UUID? = nil,
        isAuthenticated: Bool = true,
        email: String? = "dev@unbound.computer",
        dependencyStatus: DependencyCheckStatus = .satisfied,
        isGhInstalled: Bool? = true
    ) {
        self.daemonConnectionState = .connected
        self.isAuthenticated = isAuthenticated
        self.hasStoredSession = isAuthenticated
        self.authState = isAuthenticated ? .loggedIn : .notLoggedIn
        self.currentUserEmail = email
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
    /// Currently selected repository.
    var selectedRepository: Repository? {
        guard let id = selectedRepositoryId else { return nil }
        return repositories.first { $0.id == id }
    }

    /// Currently selected session.
    var selectedSession: Session? {
        guard let id = selectedSessionId else { return nil }
        return session(id: id)
    }

    /// Sessions for currently selected repository.
    var selectedRepositorySessions: [Session] {
        guard let id = selectedRepositoryId else { return [] }
        return sessionsForRepository(id)
    }
}
