//
//  SessionStateManager.swift
//  unbound-macos
//
//  Registry of per-session live states.
//  Provides get-or-create semantics so views can access session state
//  without worrying about lifecycle. Switching sessions in the UI
//  simply changes which SessionLiveState the ChatPanel reads from.
//

import Foundation
import Logging
import Observation
import OpenTelemetryApi

private let logger = Logger(label: "app.session")

@Observable
class SessionStateManager {

    // MARK: - State Registry

    private var states: [UUID: SessionLiveState] = [:]
    @ObservationIgnored private var pendingSessionOpenScopes: [UUID: TracingService.Scope] = [:]

    // MARK: - Access

    /// Get or create state for a session. Creates on first access.
    func state(for sessionId: UUID) -> SessionLiveState {
        if let existing = states[sessionId] {
            if let pendingScope = pendingSessionOpenScopes.removeValue(forKey: sessionId) {
                existing.beginSessionOpen(scope: pendingScope)
            }
            return existing
        }

        let newState = SessionLiveState(sessionId: sessionId)
        if let pendingScope = pendingSessionOpenScopes.removeValue(forKey: sessionId) {
            newState.beginSessionOpen(scope: pendingScope)
        }
        states[sessionId] = newState
        logger.debug("Created live state for session \(sessionId)")
        return newState
    }

    /// Get state only if it already exists (for sidebar - don't create on read).
    func stateIfExists(for sessionId: UUID) -> SessionLiveState? {
        states[sessionId]
    }

    // MARK: - Lifecycle

    /// Remove state when session is deleted.
    func remove(sessionId: UUID) {
        if let pendingScope = pendingSessionOpenScopes.removeValue(forKey: sessionId) {
            TracingService.cancelScope(
                pendingScope,
                attributes: ["result.detail": .string("session_removed")]
            )
        }
        if let state = states.removeValue(forKey: sessionId) {
            state.cancelSessionOpen(resultDetail: "session_removed")
            state.deactivate()
            logger.debug("Removed live state for session \(sessionId)")
        }
    }

    /// Deactivate all sessions (on app termination / disconnect).
    func deactivateAll() {
        for (_, scope) in pendingSessionOpenScopes {
            TracingService.cancelScope(
                scope,
                attributes: ["result.detail": .string("deactivate_all")]
            )
        }
        pendingSessionOpenScopes.removeAll()
        for (_, state) in states {
            state.cancelSessionOpen(resultDetail: "deactivate_all")
            state.deactivate()
        }
        states.removeAll()
        logger.info("Deactivated all session states")
    }

    func beginSessionOpen(
        sessionId: UUID,
        repositoryId: UUID?,
        source: UserIntentSource,
        userIdHash: String?,
        workspaceId: String?
    ) -> TracingService.Scope {
        cancelSessionOpenScopes(except: sessionId)

        var attributes: [String: AttributeValue] = [
            "session.id": .string(sessionId.uuidString.lowercased())
        ]
        if let repositoryId {
            let value = repositoryId.uuidString.lowercased()
            attributes["repository.id"] = .string(value)
            attributes["workspace.id"] = .string(workspaceId ?? value)
        } else if let workspaceId {
            attributes["workspace.id"] = .string(workspaceId)
        }
        if let userIdHash {
            attributes["user.id_hash"] = .string(userIdHash)
        }

        let scope = TracingService.startUserIntentScope(
            name: "session.open",
            source: source,
            parentScope: TracingService.currentIntentScope,
            attributes: attributes
        )

        if let existing = states[sessionId] {
            existing.beginSessionOpen(scope: scope)
        } else {
            pendingSessionOpenScopes[sessionId] = scope
        }

        return scope
    }

    private func cancelSessionOpenScopes(except sessionId: UUID?) {
        let pendingToCancel = pendingSessionOpenScopes
            .filter { $0.key != sessionId }
            .map { ($0.key, $0.value) }
        for (pendingSessionId, scope) in pendingToCancel {
            TracingService.cancelScope(
                scope,
                attributes: ["result.detail": .string("superseded")]
            )
            pendingSessionOpenScopes.removeValue(forKey: pendingSessionId)
        }

        for (existingSessionId, state) in states where existingSessionId != sessionId {
            state.cancelSessionOpen(resultDetail: "superseded")
        }
    }

    // MARK: - Preview Support

    #if DEBUG
    /// Register a pre-configured SessionLiveState for Canvas previews.
    /// Bypasses the get-or-create lifecycle by injecting state directly.
    func registerForPreview(sessionId: UUID, state: SessionLiveState) {
        states[sessionId] = state
    }
    #endif
}
