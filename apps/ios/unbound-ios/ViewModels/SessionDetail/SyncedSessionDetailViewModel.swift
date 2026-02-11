//
//  SyncedSessionDetailViewModel.swift
//  unbound-ios
//
//  View model for synced session detail rendering.
//

import Foundation
import Logging
import Observation

private let sessionDetailLogger = Logger(label: "app.ui.session-detail")

@MainActor
@Observable
final class SyncedSessionDetailViewModel {
    private let session: SyncedSession
    private let messageService: SessionDetailMessageLoading
    private let remoteCommandService: RemoteCommandService

    private(set) var messages: [Message] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var decryptedMessageCount = 0
    var inputText = ""
    private(set) var isSending = false
    private(set) var isStopping = false
    private(set) var commandError: String?

    private var hasLoaded = false
    private var realtimeUpdatesTask: Task<Void, Never>?

    var canSendMessage: Bool {
        session.deviceId != nil && !isSending && !isStopping
    }

    var canStopClaude: Bool {
        session.deviceId != nil && !isStopping
    }

    init(
        session: SyncedSession,
        messageService: SessionDetailMessageLoading? = nil,
        remoteCommandService: RemoteCommandService? = nil
    ) {
        self.session = session
        self.messageService = messageService ?? SessionDetailMessageService()
        self.remoteCommandService = remoteCommandService ?? .shared
    }

    func start() async {
        await loadMessages()
        startRealtimeUpdates()
    }

    func loadMessages(force: Bool = false) async {
        if isLoading {
            return
        }
        if hasLoaded && !force {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let result = try await messageService.loadMessages(sessionId: session.id)
            messages = result.messages
            decryptedMessageCount = result.decryptedMessageCount
        } catch let error as SessionDetailMessageError {
            sessionDetailLogger.error(
                "Failed to load/decrypt session \(self.session.id): \(error.localizedDescription)"
            )
            errorMessage = error.localizedDescription
        } catch {
            sessionDetailLogger.error(
                "Failed to load/decrypt session \(self.session.id): \(error.localizedDescription)"
            )
            errorMessage = error.localizedDescription
        }
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
                content: content
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

    func dismissError() {
        commandError = nil
    }

    func stopRealtimeUpdates() {
        realtimeUpdatesTask?.cancel()
        realtimeUpdatesTask = nil
    }

    private func startRealtimeUpdates() {
        guard realtimeUpdatesTask == nil else {
            return
        }

        realtimeUpdatesTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                for try await result in self.messageService.messageUpdates(sessionId: self.session.id) {
                    self.messages = result.messages
                    self.decryptedMessageCount = result.decryptedMessageCount
                    self.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                sessionDetailLogger.error(
                    "Realtime session detail stream failed for session \(self.session.id): \(error.localizedDescription)"
                )
                if self.messages.isEmpty {
                    self.errorMessage = error.localizedDescription
                }
            }

            self.realtimeUpdatesTask = nil
        }
    }
}
