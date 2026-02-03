//
//  SessionListView.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct SessionListView: View {
    @State private var sessions = WatchMockData.sessions
    @State private var selectedSession: WatchSession?

    var activeSessions: [WatchSession] {
        sessions.filter { $0.status.isActive }
    }

    var completedSessions: [WatchSession] {
        sessions.filter { !$0.status.isActive }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: WatchSession.self) { session in
                SessionDetailView(session: binding(for: session))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: WatchTheme.spacingM) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No Sessions")
                .font(.system(size: 15, weight: .medium))

            Text("Start a Claude session on your Mac")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var sessionList: some View {
        List {
            if !activeSessions.isEmpty {
                Section {
                    ForEach(activeSessions) { session in
                        NavigationLink(value: session) {
                            SessionRowView(session: session)
                        }
                    }
                } header: {
                    Label("Active", systemImage: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }

            if !completedSessions.isEmpty {
                Section {
                    ForEach(completedSessions) { session in
                        NavigationLink(value: session) {
                            SessionRowView(session: session)
                        }
                    }
                } header: {
                    Label("Recent", systemImage: "clock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.carousel)
    }

    private func binding(for session: WatchSession) -> Binding<WatchSession> {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            fatalError("Session not found")
        }
        return $sessions[index]
    }
}

#Preview("Session List") {
    SessionListView()
}

#Preview("Empty State") {
    NavigationStack {
        VStack(spacing: WatchTheme.spacingM) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No Sessions")
                .font(.system(size: 15, weight: .medium))

            Text("Start a Claude session on your Mac")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Sessions")
    }
}
