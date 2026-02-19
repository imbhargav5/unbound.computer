//
//  ClaudeSyncedSessionDetailViewModel.swift
//  unbound-ios
//
//  View model for synced session detail rendering.
//

import MobileClaudeCodeConversationTimeline
import Foundation
import Logging
import Observation

private let sessionDetailLogger = Logger(label: "app.ui.session-detail")

struct SessionCompletionSummary: Equatable {
    let outcomeLabel: String
    let summaryText: String?
    let turns: Int?
    let totalTokens: Int?
    let totalCostUSD: Double?
    let durationMs: Int?

    static func latest(from entries: [ClaudeConversationTimelineEntry]) -> SessionCompletionSummary? {
        for entry in entries.reversed() where entry.role == .result {
            guard let resultBlock = entry.blocks.reversed().compactMap({ block -> ClaudeResultBlock? in
                guard case .result(let result) = block else { return nil }
                return result
            }).first else {
                continue
            }

            guard !resultBlock.isError else { return nil }

            let summaryText = normalizedText(resultBlock.text)
            let turns = resultBlock.metrics?.numTurns
            let totalTokens = resultBlock.metrics?.usage?.totalTokens
            let totalCostUSD = resultBlock.metrics?.totalCostUSD
            let durationMs = resultBlock.metrics?.bestDurationMs

            if summaryText == nil,
               turns == nil,
               totalTokens == nil,
               totalCostUSD == nil,
               durationMs == nil {
                return nil
            }

            return SessionCompletionSummary(
                outcomeLabel: resultBlock.metrics?.stopReason ?? "end_turn",
                summaryText: summaryText,
                turns: turns,
                totalTokens: totalTokens,
                totalCostUSD: totalCostUSD,
                durationMs: durationMs
            )
        }

        return nil
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
@Observable
final class ClaudeSyncedSessionDetailViewModel {
    private let session: SyncedSession
    private let claudeState: ClaudeCodingSessionState
    private let runtimeStatusService: SessionDetailRuntimeStatusStreaming
    private let remoteCommandService: RemoteCommandService
    private let presenceService: DevicePresenceService

    var messages: [Message] {
        ClaudeTimelineMessageMapper.mapEntries(claudeState.timeline)
    }

    var latestCompletionSummary: SessionCompletionSummary? {
        SessionCompletionSummary.latest(from: claudeState.timeline)
    }

    var isLoading: Bool {
        claudeState.isLoading
    }

    var errorMessage: String? {
        claudeState.errorMessage
    }

    var decryptedMessageCount: Int {
        claudeState.decryptedMessageCount
    }
    var inputText = ""
    private let planModeDefaultsKey: String
    var isPlanModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPlanModeEnabled, forKey: planModeDefaultsKey)
        }
    }
    private(set) var isSending = false
    private(set) var isStopping = false
    private(set) var isCommitting = false
    private(set) var isPushing = false
    private(set) var commandError: String?
    private(set) var commandNotice: String?
    private(set) var pullRequests: [RemotePullRequest] = []
    private(set) var selectedPullRequest: RemotePullRequest?
    private(set) var selectedPullRequestChecks: PRChecksResult?
    var prTitle = ""
    var prBody = ""
    var prMergeMethod = "squash"
    private(set) var isLoadingPullRequests = false
    private(set) var isCreatingPullRequest = false
    private(set) var isMergingPullRequest = false
    private(set) var runtimeStatus: SessionDetailRuntimeStatusEnvelope?

    private var hasLoaded = false
    private var runtimeStatusUpdatesTask: Task<Void, Never>?

    var codingSessionStatus: SessionDetailRuntimeStatus {
        runtimeStatus?.codingSession.status ?? .notAvailable
    }

    var codingSessionErrorMessage: String? {
        runtimeStatus?.normalizedErrorMessage
    }

    var daemonAvailability: DeviceDaemonAvailability {
        guard let deviceId = session.deviceId else {
            return .unknown
        }
        return presenceService.daemonAvailability(id: deviceId.uuidString.lowercased())
    }

    var isDaemonOffline: Bool {
        daemonAvailability == .offline
    }

    var inputPlaceholder: String {
        isDaemonOffline ? "Daemon offline" : "Message Claude..."
    }

    var canSendMessage: Bool {
        session.deviceId != nil
            && daemonAvailability != .offline
            && !isSending
            && !isStopping
    }

    var canStopClaude: Bool {
        session.deviceId != nil
            && daemonAvailability != .offline
            && (codingSessionStatus == .running || codingSessionStatus == .waiting)
            && !isStopping
    }

    var canRunPRActions: Bool {
        session.deviceId != nil
            && daemonAvailability != .offline
            && !isSending
            && !isStopping
            && !isCreatingPullRequest
            && !isMergingPullRequest
            && !isCommitting
            && !isPushing
    }

    init(
        session: SyncedSession,
        claudeMessageSource: ClaudeSessionMessageSource? = nil,
        runtimeStatusService: SessionDetailRuntimeStatusStreaming? = nil,
        remoteCommandService: RemoteCommandService? = nil,
        presenceService: DevicePresenceService? = nil
    ) {
        self.session = session
        self.planModeDefaultsKey = "plan_mode_\(session.id.uuidString.lowercased())"
        self.isPlanModeEnabled = UserDefaults.standard.bool(forKey: planModeDefaultsKey)
        let source = claudeMessageSource ?? ClaudeRemoteSessionMessageSource()
        self.claudeState = ClaudeCodingSessionState(source: source)
        self.runtimeStatusService = runtimeStatusService ?? AblyRuntimeStatusService()
        self.remoteCommandService = remoteCommandService ?? .shared
        self.presenceService = presenceService ?? .shared
    }

    func start() async {
        await loadMessages()
        await refreshPullRequests()
        startRuntimeStatusUpdates()
    }

    func loadMessages(force: Bool = false) async {
        if hasLoaded && !force {
            return
        }

        if force {
            await claudeState.reload()
            return
        }

        await claudeState.start(sessionId: session.id)
        hasLoaded = true
    }

    func sendMessage() async {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let deviceId = session.deviceId else { return }
        guard !isSending else { return }

        isSending = true
        commandError = nil
        inputText = ""

        defer { isSending = false }

        do {
            let result = try await remoteCommandService.sendMessage(
                targetDeviceId: deviceId.uuidString.lowercased(),
                sessionId: session.id.uuidString.lowercased(),
                content: content,
                permissionMode: isPlanModeEnabled ? "plan" : nil
            )
            sessionDetailLogger.info("Message sent to session \(result.sessionId)")
        } catch {
            sessionDetailLogger.error("Failed to send message: \(error.localizedDescription)")
            commandError = error.localizedDescription
        }
    }

    func stopClaude() async {
        guard let deviceId = session.deviceId else { return }
        guard !isStopping else { return }

        isStopping = true
        commandError = nil

        defer { isStopping = false }

        do {
            let result = try await remoteCommandService.stopClaude(
                targetDeviceId: deviceId.uuidString.lowercased(),
                sessionId: session.id.uuidString.lowercased()
            )
            sessionDetailLogger.info("Claude stopped for session, stopped=\(result.stopped)")
        } catch {
            sessionDetailLogger.error("Failed to stop Claude: \(error.localizedDescription)")
            commandError = error.localizedDescription
        }
    }

    func commitChanges(message: String, stageAll: Bool) async {
        guard let deviceId = session.deviceId else { return }
        guard canRunPRActions else { return }
        let commitMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commitMessage.isEmpty else { return }

        isCommitting = true
        commandError = nil
        commandNotice = nil

        defer { isCommitting = false }

        do {
            let result = try await remoteCommandService.commitChanges(
                targetDeviceId: deviceId.uuidString.lowercased(),
                sessionId: session.id.uuidString.lowercased(),
                message: commitMessage,
                stageAll: stageAll
            )
            commandNotice = "Committed \(result.shortOid)"
        } catch {
            sessionDetailLogger.error("Failed to commit changes: \(error.localizedDescription)")
            commandError = error.localizedDescription
        }
    }

    func pushChanges(remote: String?, branch: String?) async {
        guard let deviceId = session.deviceId else { return }
        guard canRunPRActions else { return }

        isPushing = true
        commandError = nil
        commandNotice = nil

        defer { isPushing = false }

        do {
            let result = try await remoteCommandService.pushChanges(
                targetDeviceId: deviceId.uuidString.lowercased(),
                sessionId: session.id.uuidString.lowercased(),
                remote: remote?.trimmingCharacters(in: .whitespacesAndNewlines),
                branch: branch?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let target = "\(result.remote)/\(result.branch)"
            commandNotice = result.success ? "Pushed \(target)" : "Push failed for \(target)"
        } catch {
            sessionDetailLogger.error("Failed to push changes: \(error.localizedDescription)")
            commandError = error.localizedDescription
        }
    }

    func refreshPullRequests() async {
        guard let deviceId = session.deviceId else { return }
        guard !isLoadingPullRequests else { return }

        isLoadingPullRequests = true
        defer { isLoadingPullRequests = false }

        do {
            let result = try await remoteCommandService.listPRs(
                targetDeviceId: deviceId.uuidString.lowercased(),
                sessionId: session.id.uuidString.lowercased(),
                state: "open",
                limit: 20
            )
            pullRequests = result.pullRequests
            if let selected = selectedPullRequest,
               let refreshed = pullRequests.first(where: { $0.number == selected.number }) {
                selectedPullRequest = refreshed
            } else {
                selectedPullRequest = pullRequests.first
            }
            commandError = nil
            await refreshSelectedPullRequestChecks()
        } catch {
            sessionDetailLogger.error("Failed to refresh pull requests: \(error.localizedDescription)")
            commandError = error.localizedDescription
        }
    }

    func createPullRequest() async {
        guard let deviceId = session.deviceId else { return }
        guard canRunPRActions else { return }
        let title = prTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isCreatingPullRequest = true
        defer { isCreatingPullRequest = false }

        do {
            let body = prBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await remoteCommandService.createPR(
                targetDeviceId: deviceId.uuidString.lowercased(),
                sessionId: session.id.uuidString.lowercased(),
                title: title,
                body: body.isEmpty ? nil : body
            )
            selectedPullRequest = result.pullRequest
            prTitle = ""
            prBody = ""
            commandError = nil
            await refreshPullRequests()
        } catch {
            sessionDetailLogger.error("Failed to create pull request: \(error.localizedDescription)")
            commandError = error.localizedDescription
        }
    }

    func selectPullRequest(_ pullRequest: RemotePullRequest) async {
        selectedPullRequest = pullRequest
        await refreshSelectedPullRequestChecks()
    }

    func refreshSelectedPullRequestChecks() async {
        guard let deviceId = session.deviceId else { return }
        guard let selectedPullRequest else {
            selectedPullRequestChecks = nil
            return
        }

        do {
            selectedPullRequestChecks = try await remoteCommandService.prChecks(
                targetDeviceId: deviceId.uuidString.lowercased(),
                sessionId: session.id.uuidString.lowercased(),
                selector: "\(selectedPullRequest.number)"
            )
            commandError = nil
        } catch {
            sessionDetailLogger.error("Failed to refresh PR checks: \(error.localizedDescription)")
            commandError = error.localizedDescription
        }
    }

    func mergeSelectedPullRequest(deleteBranch: Bool = false) async {
        guard let deviceId = session.deviceId else { return }
        guard let selectedPullRequest else { return }
        guard canRunPRActions else { return }

        isMergingPullRequest = true
        defer { isMergingPullRequest = false }

        do {
            let result = try await remoteCommandService.mergePR(
                targetDeviceId: deviceId.uuidString.lowercased(),
                sessionId: session.id.uuidString.lowercased(),
                selector: "\(selectedPullRequest.number)",
                mergeMethod: prMergeMethod,
                deleteBranch: deleteBranch
            )
            self.selectedPullRequest = result.pullRequest
            commandError = nil
            await refreshPullRequests()
        } catch {
            sessionDetailLogger.error("Failed to merge pull request: \(error.localizedDescription)")
            commandError = error.localizedDescription
        }
    }

    func dismissError() {
        commandError = nil
    }

    func dismissNotice() {
        commandNotice = nil
    }

    func stopRealtimeUpdates() {
        claudeState.stop()
        runtimeStatusUpdatesTask?.cancel()
        runtimeStatusUpdatesTask = nil
    }

    private func startRuntimeStatusUpdates() {
        guard runtimeStatusUpdatesTask == nil else {
            return
        }

        runtimeStatusUpdatesTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                for try await envelope in self.runtimeStatusService.subscribe(sessionId: self.session.id) {
                    guard envelope.normalizedSessionId == self.session.id.uuidString.lowercased() else {
                        continue
                    }

                    if let current = self.runtimeStatus, envelope.updatedAtMs < current.updatedAtMs {
                        continue
                    }

                    self.runtimeStatus = envelope
                }
            } catch is CancellationError {
                return
            } catch {
                sessionDetailLogger.error(
                    "Realtime runtime-status stream failed for session \(self.session.id): \(error.localizedDescription)"
                )
            }

            self.runtimeStatusUpdatesTask = nil
        }
    }
}
