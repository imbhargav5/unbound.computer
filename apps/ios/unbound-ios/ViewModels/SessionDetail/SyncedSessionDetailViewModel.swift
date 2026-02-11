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

    private(set) var messages: [Message] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var decryptedMessageCount = 0

    private var hasLoaded = false
    private var realtimeUpdatesTask: Task<Void, Never>?

    init(
        session: SyncedSession,
        messageService: SessionDetailMessageLoading? = nil
    ) {
        self.session = session
        self.messageService = messageService ?? SessionDetailMessageService()
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
