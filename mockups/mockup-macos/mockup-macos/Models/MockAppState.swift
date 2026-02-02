//
//  MockAppState.swift
//  mockup-macos
//
//  Mock application state for UI previews and testing
//

import Foundation
import SwiftUI

// MARK: - Mock App State

@Observable
class MockAppState {
    // MARK: - UI State

    var showSettings: Bool = false
    var showCommandPalette: Bool = false
    var showAddRepository: Bool = false
    var selectedSessionId: UUID?
    var selectedRepositoryId: UUID?

    // MARK: - Cached Data (Mock)

    var repositories: [Repository] = FakeData.repositories
    var sessions: [UUID: [Session]] = [:]

    // MARK: - Loading States

    var isLoadingRepositories: Bool = false
    var isLoadingSessions: Bool = false

    // MARK: - Initialization

    init() {
        // Group sessions by repository
        for session in FakeData.sessions {
            if sessions[session.repositoryId] == nil {
                sessions[session.repositoryId] = []
            }
            sessions[session.repositoryId]?.append(session)
        }

        // Auto-select first session
        if let firstSession = FakeData.sessions.first {
            selectedSessionId = firstSession.id
            selectedRepositoryId = firstSession.repositoryId
        }
    }

    // MARK: - Computed Properties

    var selectedSession: Session? {
        guard let id = selectedSessionId else { return nil }
        return sessions.values.flatMap { $0 }.first { $0.id == id }
    }

    var selectedRepository: Repository? {
        guard let id = selectedRepositoryId else { return nil }
        return repositories.first { $0.id == id }
    }

    // MARK: - Methods

    func selectSession(_ id: UUID) {
        selectedSessionId = id
        // Update selected repository based on session
        if let session = sessions.values.flatMap({ $0 }).first(where: { $0.id == id }) {
            selectedRepositoryId = session.repositoryId
        }
    }

    func sessionsForRepository(_ repositoryId: UUID) -> [Session] {
        sessions[repositoryId] ?? []
    }
}

// MARK: - Environment Key

private struct MockAppStateKey: EnvironmentKey {
    static let defaultValue = MockAppState()
}

extension EnvironmentValues {
    var mockAppState: MockAppState {
        get { self[MockAppStateKey.self] }
        set { self[MockAppStateKey.self] = newValue }
    }
}
