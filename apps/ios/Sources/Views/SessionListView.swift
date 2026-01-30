import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct SessionListView: View {
    // Using @State with @Observable (iOS 17+) instead of @StateObject with ObservableObject
    @State private var viewModel = SessionListViewModel()
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        NavigationStack {
            Group {
                if !authService.isAuthenticated {
                    authenticationView
                } else if viewModel.isLoading && viewModel.sessions.isEmpty {
                    loadingView
                } else if viewModel.sessions.isEmpty {
                    emptyStateView
                } else {
                    sessionsList
                }
            }
            .navigationTitle("Coding Sessions")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { Task { await viewModel.refreshSessions() } }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive, action: { authService.clearSession() }) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button(action: { Task { await viewModel.refreshSessions() } }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive, action: { authService.clearSession() }) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                #endif
            }
        }
        .task {
            if authService.isAuthenticated {
                await viewModel.loadSessions()
            }
        }
    }

    // MARK: - Subviews

    private var sessionsList: some View {
        List {
            ForEach(viewModel.sessions) { session in
                NavigationLink(value: session.id) {
                    SessionCard(session: session)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refreshSessions()
        }
        .navigationDestination(for: UUID.self) { sessionId in
            SessionDetailView(sessionId: sessionId)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading sessions...")
                .foregroundColor(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Sessions Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your coding sessions will appear here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { Task { await viewModel.refreshSessions() } }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding()
    }

    private var authenticationView: some View {
        AuthenticationView()
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let session: CodingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title ?? "Untitled Session")
                        .font(.headline)
                        .lineLimit(1)

                    Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                StatusBadge(status: session.status)
            }

            // Metadata
            if let deviceName = session.executorDeviceName {
                Label(deviceName, systemImage: "laptopcomputer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let projectPath = session.projectPath {
                Label(projectPath, systemImage: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Statistics
            HStack(spacing: 16) {
                if let eventCount = session.eventCount {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.caption)
                        Text("\(eventCount)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                if let toolCallCount = session.toolCallCount {
                    HStack(spacing: 4) {
                        Image(systemName: "hammer")
                            .font(.caption)
                        Text("\(toolCallCount)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                if let errorCount = session.errorCount, errorCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                        Text("\(errorCount)")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding()
        #if canImport(UIKit)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .cornerRadius(12)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        Label(status.displayName, systemImage: status.systemIcon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
    }

    private var backgroundColor: Color {
        switch status {
        case .active: return Color.green.opacity(0.2)
        case .paused: return Color.orange.opacity(0.2)
        case .completed: return Color.blue.opacity(0.2)
        case .cancelled: return Color.gray.opacity(0.2)
        case .error: return Color.red.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .active: return .green
        case .paused: return .orange
        case .completed: return .blue
        case .cancelled: return .gray
        case .error: return .red
        }
    }
}

#Preview {
    NavigationStack {
        SessionListView()
            .environmentObject(AuthenticationService.shared)
    }
}
