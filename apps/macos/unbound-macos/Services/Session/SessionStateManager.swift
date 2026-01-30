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

private let logger = Logger(label: "app.session")

@Observable
class SessionStateManager {

    // MARK: - State Registry

    private var states: [UUID: SessionLiveState] = [:]

    // MARK: - Access

    /// Get or create state for a session. Creates on first access.
    func state(for sessionId: UUID) -> SessionLiveState {
        if let existing = states[sessionId] {
            return existing
        }

        let newState = SessionLiveState(sessionId: sessionId)
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
        if let state = states.removeValue(forKey: sessionId) {
            state.deactivate()
            logger.debug("Removed live state for session \(sessionId)")
        }
    }

    /// Deactivate all sessions (on app termination / disconnect).
    func deactivateAll() {
        for (_, state) in states {
            state.deactivate()
        }
        states.removeAll()
        logger.info("Deactivated all session states")
    }
}
