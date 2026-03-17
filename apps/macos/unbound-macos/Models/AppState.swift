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

enum BoardOnboardingStep: String, Codable {
    case createCEO
    case bootstrapIssue
}

struct BoardOnboardingState: Codable, Equatable {
    var companyId: String
    var step: BoardOnboardingStep
    var ceoName: String
    var ceoTitle: String
    var bootstrapIssueTitle: String
    var bootstrapIssueDescription: String
    var ceoAgentId: String?

    static func initial(companyId: String, companyName: String? = nil) -> Self {
        Self(
            companyId: companyId,
            step: .createCEO,
            ceoName: "CEO",
            ceoTitle: "Chief Executive Officer",
            bootstrapIssueTitle: "Create your CEO HEARTBEAT.md",
            bootstrapIssueDescription: defaultBootstrapIssueDescription(companyName: companyName),
            ceoAgentId: nil
        )
    }

    static func defaultBootstrapIssueDescription(companyName: String? = nil) -> String {
        let trimmedCompanyName = companyName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let companyReference = (trimmedCompanyName?.isEmpty == false)
            ? trimmedCompanyName!
            : "this company"

        return """
        Setup yourself as the CEO for \(companyReference).

        During your first run, use the Agent home and Instructions paths provided in the run context to create or fetch your AGENTS.md, HEARTBEAT.md, SOUL.md, TOOLS.md, and MEMORY.md files.

        Make sure the CEO workspace is ready for future heartbeats, document what you created, and leave the company in a bootstrapped state for the next run.

        After you finish that setup, submit a board-native hire request for a Founding Engineer that links back to this issue. Use the board helper commands provided in the run prompt so Unbound creates the real agent record and any required approval. Do not create sibling agent directories or AGENTS.md files by hand for new hires.
        """
    }
}

enum IssuesListTab: String, Hashable, CaseIterable {
    case new
    case all

    var title: String {
        switch self {
        case .new: return "New"
        case .all: return "All"
        }
    }
}

enum IssuesRouteDestination: Hashable {
    case list
    case detail(issueId: String)

    var issueId: String? {
        switch self {
        case .list:
            return nil
        case .detail(let issueId):
            return issueId
        }
    }
}

// MARK: - App State

@MainActor
@Observable
class AppState {
    private enum PersistedKeys {
        static let themeMode = "themeMode"
        static let selectedCompanyId = "selectedCompanyId"
        static let boardOnboardingState = "boardOnboardingState"
    }

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

    var currentShell: BoardShellKind {
        if hasCompletedInitialCompanyLoad, companies.isEmpty {
            return .firstCompanySetup
        }
        if boardOnboardingState != nil {
            return .ceoSetupRequired
        }
        if let selectedCompany, selectedCompany.ceoAgentId == nil {
            return .ceoSetupRequired
        }
        return selectedScreen == .workspaces ? .workspace : .companyDashboard
    }

    var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: PersistedKeys.themeMode)
        }
    }

    let localSettings = LocalSettings.shared

    var showSettings: Bool = false
    var showCommandPalette: Bool = false
    var selectedScreen: AppScreen = .dashboard
    var selectedSessionId: UUID?
    var selectedRepositoryId: UUID?
    var selectedCompanyId: String?
    var selectedBoardWorkspaceId: String?
    var selectedIssueId: String?
    var selectedProjectId: String?
    var selectedAgentId: String?
    var selectedApprovalId: String?
    var selectedIssuesListTab: IssuesListTab = .new
    var issuesRouteDestination: IssuesRouteDestination = .list
    private(set) var boardOnboardingState: BoardOnboardingState?

    private(set) var repositories: [Repository] = []
    private(set) var sessions: [UUID: [Session]] = [:]
    private(set) var companies: [DaemonCompany] = []
    private(set) var workspaces: [DaemonWorkspace] = []
    private(set) var agents: [DaemonAgent] = []
    private(set) var goals: [DaemonGoal] = []
    private(set) var issues: [DaemonIssue] = []
    private(set) var approvals: [DaemonApproval] = []
    private(set) var projects: [DaemonProject] = []
    private(set) var issueComments: [String: [DaemonIssueComment]] = [:]

    private(set) var isLoadingRepositories: Bool = false
    private(set) var isLoadingSessions: Bool = false
    private(set) var isLoadingBoardData: Bool = false
    private(set) var hasCompletedInitialCompanyLoad: Bool = false
    private(set) var boardError: String?

    init() {
        logger.info("AppState.init started")

        if let savedTheme = UserDefaults.standard.string(forKey: PersistedKeys.themeMode),
           let theme = ThemeMode(rawValue: savedTheme) {
            self.themeMode = theme
        } else {
            self.themeMode = .system
        }

        self.selectedCompanyId = UserDefaults.standard.string(forKey: PersistedKeys.selectedCompanyId)
        self.boardOnboardingState = Self.loadBoardOnboardingState()

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
                await loadBoardDataAsync()
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
            await loadBoardDataAsync()
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

    func loadBoardDataAsync() async {
        logger.info("Loading board data from daemon...")
        await refreshCompanies()
        guard let selectedCompanyId else {
            clearCompanyScopedBoardData()
            return
        }
        await refreshCompanyScopedBoardData(companyId: selectedCompanyId)
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

    func refreshCompanies() async {
        isLoadingBoardData = true
        defer {
            isLoadingBoardData = false
            hasCompletedInitialCompanyLoad = true
        }

        do {
            companies = try await daemonClient.listCompanies()
            boardError = nil
            let onboardingCompanyId = boardOnboardingState?.companyId
            let preferredCompanyId = onboardingCompanyId
                ?? selectedCompanyId
                ?? UserDefaults.standard.string(forKey: PersistedKeys.selectedCompanyId)
            if let preferredCompanyId,
               companies.contains(where: { $0.id == preferredCompanyId }) {
                selectedCompanyId = preferredCompanyId
                persistSelectedCompanyId(preferredCompanyId)
            } else {
                selectedCompanyId = companies.first?.id
            }
            reconcileBoardOnboardingState(with: companies)
            persistSelectedCompanyId(selectedCompanyId)
        } catch {
            boardError = error.localizedDescription
            logger.error("Failed to load companies: \(error)")
        }
    }

    func selectCompany(_ companyId: String?) async {
        guard selectedCompanyId != companyId else { return }
        selectedCompanyId = companyId
        persistSelectedCompanyId(companyId)
        selectedSessionId = nil
        selectedRepositoryId = nil
        selectedBoardWorkspaceId = nil
        selectedIssueId = nil
        selectedProjectId = nil
        selectedAgentId = nil
        selectedApprovalId = nil
        issuesRouteDestination = .list
        issueComments = [:]

        guard let companyId else {
            clearCompanyScopedBoardData()
            return
        }

        await refreshCompanyScopedBoardData(companyId: companyId)
    }

    func refreshCompanyScopedBoardData(companyId: String? = nil) async {
        guard let companyId = companyId ?? selectedCompanyId else {
            clearCompanyScopedBoardData()
            return
        }

        isLoadingBoardData = true
        defer { isLoadingBoardData = false }

        do {
            let loadedWorkspaces = try await daemonClient.listWorkspaces(companyId: companyId)
            let loadedAgents = try await daemonClient.listAgents(companyId: companyId)
            let loadedGoals = try await daemonClient.listGoals(companyId: companyId)
            let loadedProjects = try await daemonClient.listProjects(companyId: companyId)
            let loadedIssues = try await daemonClient.listIssues(params: ["company_id": companyId])
            let loadedApprovals = try await daemonClient.listApprovals(companyId: companyId)

            workspaces = loadedWorkspaces
            agents = loadedAgents
            goals = loadedGoals
            projects = loadedProjects
            issues = loadedIssues
            approvals = loadedApprovals
            boardError = nil

            if let selectedBoardWorkspaceId,
               !workspaces.contains(where: { $0.id == selectedBoardWorkspaceId }) {
                self.selectedBoardWorkspaceId = workspaces.first?.id
            } else if self.selectedBoardWorkspaceId == nil {
                self.selectedBoardWorkspaceId = workspaces.first?.id
            }

            if let selectedIssueId,
               !issues.contains(where: { $0.id == selectedIssueId }) {
                self.selectedIssueId = nil
            }

            reconcileIssuesRouteState()

            if let selectedAgentId,
               !agents.contains(where: { $0.id == selectedAgentId }) {
                self.selectedAgentId = preferredAgentId(from: agents)
            } else if self.selectedAgentId == nil {
                self.selectedAgentId = preferredAgentId(from: agents)
            }

            if let selectedProjectId,
               !projects.contains(where: { $0.id == selectedProjectId }) {
                self.selectedProjectId = projects.first?.id
            }

            if let selectedApprovalId,
               !approvals.contains(where: { $0.id == selectedApprovalId }) {
                self.selectedApprovalId = approvals.first?.id
            }

            if let workspaceId = self.selectedBoardWorkspaceId,
               let sessionId = UUID(uuidString: workspaceId) {
                selectSession(sessionId, source: .sidebar)
            }
        } catch {
            boardError = error.localizedDescription
            logger.error("Failed to load company-scoped board data for \(companyId): \(error)")
        }
    }

    func refreshIssueComments(issueId: String) async {
        do {
            issueComments[issueId] = try await daemonClient.listIssueComments(issueId: issueId)
        } catch {
            logger.error("Failed to load comments for issue \(issueId): \(error)")
        }
    }

    func selectBoardWorkspace(_ workspace: DaemonWorkspace) async {
        selectedBoardWorkspaceId = workspace.id

        if let repositoryId = UUID(uuidString: workspace.repositoryId) {
            if !repositories.contains(where: { $0.id == repositoryId }) {
                await refreshRepositories()
            }

            let knownSessionIds = Set((sessions[repositoryId] ?? []).map(\.id))
            if let workspaceSessionId = UUID(uuidString: workspace.sessionId),
               !knownSessionIds.contains(workspaceSessionId) {
                await refreshSessions(for: repositoryId)
            }

            if let workspaceSessionId = UUID(uuidString: workspace.sessionId) {
                selectSession(workspaceSessionId, source: .sidebar)
            }
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
        companies = []
        workspaces = []
        agents = []
        goals = []
        issues = []
        approvals = []
        projects = []
        issueComments = [:]
        selectedCompanyId = nil
        hasCompletedInitialCompanyLoad = false
        selectedBoardWorkspaceId = nil
        selectedIssueId = nil
        selectedProjectId = nil
        selectedAgentId = nil
        selectedApprovalId = nil
        issuesRouteDestination = .list
    }

    private func clearCompanyScopedBoardData() {
        workspaces = []
        agents = []
        goals = []
        issues = []
        approvals = []
        projects = []
        issueComments = [:]
        selectedSessionId = nil
        selectedRepositoryId = nil
        selectedBoardWorkspaceId = nil
        selectedIssueId = nil
        selectedProjectId = nil
        selectedAgentId = nil
        selectedApprovalId = nil
        issuesRouteDestination = .list
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

    // MARK: - Board Mutations

    func createCompany(
        name: String,
        description: String? = nil,
        budgetMonthlyCents: Int? = nil,
        brandColor: String? = nil,
        requireBoardApprovalForNewAgents: Bool? = nil
    ) async throws -> DaemonCompany {
        let company = try await daemonClient.createCompany(
            name: name,
            description: description,
            budgetMonthlyCents: budgetMonthlyCents,
            brandColor: brandColor,
            requireBoardApprovalForNewAgents: requireBoardApprovalForNewAgents
        )
        beginBoardOnboarding(for: company.id, companyName: company.name)
        await refreshCompanies()
        await selectCompany(company.id)
        selectedScreen = .dashboard
        return company
    }

    func createAgent(params: [String: Any]) async throws -> DaemonAgent {
        let agent = try await daemonClient.createAgent(params: params)
        await refreshCompanies()
        await refreshCompanyScopedBoardData(companyId: agent.companyId)
        selectedAgentId = agent.id
        return agent
    }

    func createAgentHire(params: [String: Any]) async throws -> DaemonAgent {
        let agent = try await daemonClient.createAgentHire(params: params)
        await refreshCompanies()
        await refreshCompanyScopedBoardData(companyId: agent.companyId)
        selectedAgentId = agent.id
        return agent
    }

    func createProject(params: [String: Any]) async throws -> DaemonProject {
        let project = try await daemonClient.createProject(params: params)
        await refreshRepositories()
        await refreshCompanyScopedBoardData(companyId: project.companyId)
        selectedProjectId = project.id
        return project
    }

    func createIssue(params: [String: Any]) async throws -> DaemonIssue {
        let issue = try await daemonClient.createIssue(params: params)
        await refreshCompanyScopedBoardData(companyId: issue.companyId)
        showIssueDetail(issueId: issue.id)
        return issue
    }

    func updateIssue(params: [String: Any]) async throws -> DaemonIssue {
        let issue = try await daemonClient.updateIssue(params: params)
        await refreshCompanyScopedBoardData(companyId: issue.companyId)
        showIssueDetail(issueId: issue.id)
        return issue
    }

    func showIssuesList(tab: IssuesListTab? = nil) {
        if let tab {
            selectedIssuesListTab = tab
        }
        issuesRouteDestination = .list
        selectedScreen = .issues
    }

    func showIssueDetail(issueId: String) {
        selectedIssueId = issueId
        issuesRouteDestination = .detail(issueId: issueId)
        selectedScreen = .issues
    }

    func reconcileIssuesRouteState() {
        if let selectedIssueId,
           !issues.contains(where: { $0.id == selectedIssueId }) {
            self.selectedIssueId = nil
        }

        switch issuesRouteDestination {
        case .list:
            return
        case .detail(let issueId):
            guard issues.contains(where: { $0.id == issueId }) else {
                issuesRouteDestination = .list
                return
            }
            if selectedIssueId != issueId {
                selectedIssueId = issueId
            }
        }
    }

    func addIssueComment(params: [String: Any]) async throws -> DaemonIssueComment {
        let comment = try await daemonClient.addIssueComment(params: params)
        await refreshIssueComments(issueId: comment.issueId)
        return comment
    }

    func checkoutIssue(issueId: String) async throws -> DaemonWorkspace {
        let workspace = try await daemonClient.checkoutIssue(issueId: issueId)
        await refreshRepositories()
        if let repositoryId = UUID(uuidString: workspace.repositoryId) {
            await refreshSessions(for: repositoryId)
        }
        if let companyId = workspace.companyId {
            await refreshCompanyScopedBoardData(companyId: companyId)
        }
        selectedBoardWorkspaceId = workspace.id
        if let sessionId = UUID(uuidString: workspace.sessionId) {
            selectSession(sessionId, source: .sidebar)
        }
        selectedScreen = .workspaces
        return workspace
    }

    func approveApproval(approvalId: String, decisionNote: String? = nil) async throws -> DaemonApproval {
        var params: [String: Any] = ["approval_id": approvalId]
        if let decisionNote {
            params["decision_note"] = decisionNote
        }
        let approval = try await daemonClient.approveApproval(params: params)
        await refreshCompanyScopedBoardData(companyId: approval.companyId)
        selectedApprovalId = approval.id
        return approval
    }

    #if DEBUG
    func configureForPreview(
        repositories: [Repository] = [],
        sessions: [UUID: [Session]] = [:],
        selectedRepositoryId: UUID? = nil,
        selectedSessionId: UUID? = nil,
        companies: [DaemonCompany] = [],
        agents: [DaemonAgent] = [],
        issues: [DaemonIssue] = [],
        selectedCompanyId: String? = nil,
        selectedIssueId: String? = nil,
        hasCompletedInitialCompanyLoad: Bool = false,
        selectedScreen: AppScreen? = nil,
        selectedIssuesListTab: IssuesListTab = .new,
        issuesRouteDestination: IssuesRouteDestination = .list,
        boardOnboardingState: BoardOnboardingState? = nil,
        dependencyStatus: DependencyCheckStatus = .satisfied,
        isGhInstalled: Bool? = true
    ) {
        self.daemonConnectionState = .connected
        self.repositories = repositories
        self.sessions = sessions
        self.selectedRepositoryId = selectedRepositoryId
        self.selectedSessionId = selectedSessionId
        self.companies = companies
        self.agents = agents
        self.issues = issues
        self.selectedCompanyId = selectedCompanyId ?? companies.first?.id
        self.selectedIssueId = selectedIssueId
        self.hasCompletedInitialCompanyLoad = hasCompletedInitialCompanyLoad
        if let selectedScreen {
            self.selectedScreen = selectedScreen
        }
        self.selectedIssuesListTab = selectedIssuesListTab
        self.issuesRouteDestination = issuesRouteDestination
        self.boardOnboardingState = boardOnboardingState
        self.dependencyStatus = dependencyStatus
        self.isGhInstalled = isGhInstalled
        reconcileIssuesRouteState()
    }
    #endif
}

private extension AppState {
    static func loadBoardOnboardingState() -> BoardOnboardingState? {
        guard let data = UserDefaults.standard.data(forKey: PersistedKeys.boardOnboardingState) else {
            return nil
        }

        return try? JSONDecoder().decode(BoardOnboardingState.self, from: data)
    }

    func persistBoardOnboardingState() {
        guard let boardOnboardingState else {
            UserDefaults.standard.removeObject(forKey: PersistedKeys.boardOnboardingState)
            return
        }

        do {
            let data = try JSONEncoder().encode(boardOnboardingState)
            UserDefaults.standard.set(data, forKey: PersistedKeys.boardOnboardingState)
        } catch {
            logger.error("Failed to persist board onboarding state: \(error)")
        }
    }

    func persistSelectedCompanyId(_ companyId: String?) {
        if let companyId {
            UserDefaults.standard.set(companyId, forKey: PersistedKeys.selectedCompanyId)
        } else {
            UserDefaults.standard.removeObject(forKey: PersistedKeys.selectedCompanyId)
        }
    }

    func reconcileBoardOnboardingState(with companies: [DaemonCompany]) {
        guard var boardOnboardingState else { return }
        guard let company = companies.first(where: { $0.id == boardOnboardingState.companyId }) else {
            self.boardOnboardingState = nil
            persistBoardOnboardingState()
            return
        }

        if selectedCompanyId != company.id {
            selectedCompanyId = company.id
            persistSelectedCompanyId(company.id)
        }

        if let ceoAgentId = company.ceoAgentId {
            boardOnboardingState.step = .bootstrapIssue
            boardOnboardingState.ceoAgentId = ceoAgentId
        } else {
            boardOnboardingState.step = .createCEO
            boardOnboardingState.ceoAgentId = nil
        }

        if self.boardOnboardingState != boardOnboardingState {
            self.boardOnboardingState = boardOnboardingState
            persistBoardOnboardingState()
        }
    }

    func preferredAgentId(from agents: [DaemonAgent]) -> String? {
        if let ceoAgentId = selectedCompany?.ceoAgentId,
           agents.contains(where: { $0.id == ceoAgentId }) {
            return ceoAgentId
        }

        if let fallbackCeoId = agents.first(where: { $0.role.caseInsensitiveCompare("ceo") == .orderedSame })?.id {
            return fallbackCeoId
        }

        return agents.first?.id
    }
}

// MARK: - Convenience Accessors

extension AppState {
    func beginBoardOnboarding(for companyId: String, companyName: String? = nil) {
        boardOnboardingState = BoardOnboardingState.initial(companyId: companyId, companyName: companyName)
        persistBoardOnboardingState()
    }

    func ensureBoardOnboardingStateForSelectedCompany() {
        guard let selectedCompany else { return }

        if let boardOnboardingState, boardOnboardingState.companyId == selectedCompany.id {
            reconcileBoardOnboardingState(with: companies)
            return
        }

        if selectedCompany.ceoAgentId == nil {
            beginBoardOnboarding(for: selectedCompany.id, companyName: selectedCompany.name)
        }
    }

    func updateBoardOnboardingDraft(
        ceoName: String? = nil,
        ceoTitle: String? = nil,
        bootstrapIssueTitle: String? = nil,
        bootstrapIssueDescription: String? = nil
    ) {
        guard var boardOnboardingState else { return }

        if let ceoName {
            boardOnboardingState.ceoName = ceoName
        }
        if let ceoTitle {
            boardOnboardingState.ceoTitle = ceoTitle
        }
        if let bootstrapIssueTitle {
            boardOnboardingState.bootstrapIssueTitle = bootstrapIssueTitle
        }
        if let bootstrapIssueDescription {
            boardOnboardingState.bootstrapIssueDescription = bootstrapIssueDescription
        }

        self.boardOnboardingState = boardOnboardingState
        persistBoardOnboardingState()
    }

    func advanceBoardOnboardingToBootstrapIssue(ceoAgentId: String) {
        guard var boardOnboardingState else { return }
        boardOnboardingState.step = .bootstrapIssue
        boardOnboardingState.ceoAgentId = ceoAgentId
        self.boardOnboardingState = boardOnboardingState
        persistBoardOnboardingState()
    }

    func clearBoardOnboardingState() {
        boardOnboardingState = nil
        persistBoardOnboardingState()
    }

    var selectedCompany: DaemonCompany? {
        guard let id = selectedCompanyId else { return nil }
        return companies.first { $0.id == id }
    }

    var selectedBoardWorkspace: DaemonWorkspace? {
        guard let id = selectedBoardWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
    }

    var selectedIssue: DaemonIssue? {
        guard let id = selectedIssueId else { return nil }
        return issues.first { $0.id == id }
    }

    var selectedProject: DaemonProject? {
        guard let id = selectedProjectId else { return nil }
        return projects.first { $0.id == id }
    }

    var selectedAgent: DaemonAgent? {
        guard let id = selectedAgentId else { return nil }
        return agents.first { $0.id == id }
    }

    var selectedApproval: DaemonApproval? {
        guard let id = selectedApprovalId else { return nil }
        return approvals.first { $0.id == id }
    }

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
