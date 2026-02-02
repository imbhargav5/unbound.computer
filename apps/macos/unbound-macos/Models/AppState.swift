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

    // MARK: - Daemon Connection State

    private(set) var daemonConnectionState: DaemonConnectionState = .disconnected
    private(set) var daemonError: String?

    var isDaemonConnected: Bool {
        daemonConnectionState.isConnected
    }

    // MARK: - Authentication State (from daemon)

    private(set) var isAuthenticated: Bool = false
    private(set) var currentUserId: String?
    private(set) var currentUserEmail: String?

    // MARK: - UI State

    var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode")
        }
    }

    /// Local settings for font size and other UI preferences
    let localSettings = LocalSettings.shared

    var showSettings: Bool = false
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

            // If authenticated, load data
            if isAuthenticated {
                await loadDataAsync()
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
        sessionStateManager.deactivateAll()
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
        do {
            let status = try await daemonClient.getAuthStatus()
            isAuthenticated = status.authenticated
            currentUserId = status.userId
            currentUserEmail = status.email
            logger.info("Auth status: authenticated=\(status.authenticated), email=\(status.email ?? "nil")")
        } catch {
            logger.error("Failed to get auth status: \(error)")
            isAuthenticated = false
            currentUserId = nil
            currentUserEmail = nil
        }
    }

    /// Login via daemon with email and password.
    func loginWithPassword(email: String, password: String) async throws {
        try await daemonClient.loginWithPassword(email: email, password: password)
        await refreshAuthStatus()

        if isAuthenticated {
            await loadDataAsync()
        }
    }

    /// Login via daemon with OAuth provider.
    /// - Parameters:
    ///   - provider: OAuth provider ("github", "google") or "magic_link" for passwordless.
    ///   - email: Email address (required for magic_link, optional for OAuth).
    func loginWithProvider(_ provider: String, email: String? = nil) async throws {
        try await daemonClient.loginWithProvider(provider, email: email)
        await refreshAuthStatus()

        if isAuthenticated {
            await loadDataAsync()
        }
    }

    /// Logout via daemon.
    func logout() async throws {
        try await daemonClient.logout()
        isAuthenticated = false
        currentUserId = nil
        currentUserEmail = nil
        clearCachedData()
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
        sessions[repositoryId] ?? []
    }

    /// Clear all cached data.
    private func clearCachedData() {
        repositories = []
        sessions = [:]
        selectedSessionId = nil
        selectedRepositoryId = nil
    }

    // MARK: - Repository Management

    /// Add a repository.
    func addRepository(path: String) async throws -> Repository {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let daemonRepo = try await daemonClient.addRepository(name: name, path: path)
        guard let repo = daemonRepo.toRepository() else {
            throw DaemonError.decodingFailed("Invalid repository data")
        }
        repositories.append(repo)
        return repo
    }

    /// Remove a repository.
    func removeRepository(_ repositoryId: UUID) async throws {
        try await daemonClient.removeRepository(repositoryId: repositoryId.uuidString)
        repositories.removeAll { $0.id == repositoryId }
        sessions.removeValue(forKey: repositoryId)

        if selectedRepositoryId == repositoryId {
            selectedRepositoryId = nil
            selectedSessionId = nil
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
        let isWorktree = locationType == .worktree
        let daemonSession = try await daemonClient.createSession(
            repositoryId: repositoryId.uuidString,
            title: title,
            isWorktree: isWorktree
        )
        guard let session = daemonSession.toSession() else {
            throw DaemonError.decodingFailed("Invalid session data")
        }

        // Add to cache
        if sessions[repositoryId] != nil {
            sessions[repositoryId]?.append(session)
        } else {
            sessions[repositoryId] = [session]
        }

        return session
    }

    /// Delete a session.
    func deleteSession(_ sessionId: UUID, repositoryId: UUID) async throws {
        try await daemonClient.deleteSession(sessionId: sessionId.uuidString)

        // Remove live state
        sessionStateManager.remove(sessionId: sessionId)

        // Remove from cache
        sessions[repositoryId]?.removeAll { $0.id == sessionId }

        if selectedSessionId == sessionId {
            selectedSessionId = nil
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

    // MARK: - Selection

    /// Select a session and its repository.
    func selectSession(_ sessionId: UUID?) {
        selectedSessionId = sessionId

        // Find and select the repository containing this session
        if let sessionId {
            for (repoId, repoSessions) in sessions {
                if repoSessions.contains(where: { $0.id == sessionId }) {
                    selectedRepositoryId = repoId
                    break
                }
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
