//
//  WorkspacesSidebar.swift
//  unbound-macos
//
//  Shadcn-styled sessions sidebar.
//  Groups sessions by repository, then by location (main directory vs worktree).
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

// MARK: - Sessions By Location

/// Groups sessions by their location type (main directory vs worktree)
struct SessionsByLocation {
    let mainDirectorySessions: [Session]
    let worktreeSessions: [(name: String, sessions: [Session])]

    var totalCount: Int {
        mainDirectorySessions.count + worktreeSessions.reduce(0) { $0 + $1.sessions.count }
    }
}

struct WorkspacesSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var onOpenSettings: () -> Void
    var onAddRepository: () -> Void
    var onCreateSessionForRepository: (Repository, SessionLocationType) -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    // MARK: - Computed Properties (Single Source of Truth from Daemon)

    /// Active sessions from AppState (cached from daemon)
    private var sessions: [Session] {
        appState.sessions.values.flatMap { $0 }
    }

    /// Selected session based on selectedSessionId
    private var selectedSession: Session? {
        appState.selectedSession
    }

    /// Group sessions by repository, then by location (main directory vs worktree)
    /// Shows all repositories, even those without sessions
    private var sessionsByRepository: [(repository: Repository, locations: SessionsByLocation)] {
        let repositories = appState.repositories
        return repositories.map { repository in
            let repositorySessions = appState.sessionsForRepository(repository.id)

            // Split into main directory and worktree sessions
            let mainDirSessions = repositorySessions.filter { !$0.isWorktree }
            let worktreeSess = repositorySessions.filter { $0.isWorktree }

            // Group worktree sessions by their worktree name (folder name from path)
            let worktreeGroups = Dictionary(grouping: worktreeSess) { session -> String in
                guard let path = session.worktreePath else { return "Unknown" }
                return URL(fileURLWithPath: path).lastPathComponent
            }
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, sessions: $0.value) }

            let locations = SessionsByLocation(
                mainDirectorySessions: mainDirSessions,
                worktreeSessions: worktreeGroups
            )

            return (repository: repository, locations: locations)
        }
    }

    // MARK: - Session Actions

    /// Archive a session (delete via daemon for now)
    private func archiveSession(_ session: Session) {
        Task {
            do {
                try await appState.deleteSession(session.id, repositoryId: session.repositoryId)
            } catch {
                logger.error("Failed to archive session: \(error)")
            }
        }
    }

    /// Restore an archived session (not implemented for daemon yet)
    private func restoreSession(_ session: Session) {
        // TODO: Implement archive/restore in daemon
        logger.warning("Restore session not implemented in daemon mode")
    }

    /// Delete a session permanently
    private func deleteSession(_ session: Session) {
        Task {
            do {
                try await appState.deleteSession(session.id, repositoryId: session.repositoryId)
            } catch {
                logger.error("Failed to delete session: \(error)")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Agents header (top bar with fixed 64px height)
            SidebarHeader(title: "Agents") {
                // Menu action
            }

            ShadcnDivider()

            // Sessions list grouped by repository or empty state
            if sessionsByRepository.isEmpty {
                RepositoriesEmptyState(onAddRepository: onAddRepository)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(sessionsByRepository, id: \.repository.id) { group in
                            RepositoryGroup(
                                repository: group.repository,
                                locations: group.locations,
                                selectedSessionId: appState.selectedSessionId,
                                onSelectSession: { session in
                                    appState.selectedSessionId = session.id
                                },
                                onCreateSession: onCreateSessionForRepository,
                                onArchiveSession: archiveSession,
                                onDeleteSession: deleteSession
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }

                        // Archived sessions section
                        ArchivedSessionsSection(
                            onRestoreSession: restoreSession,
                            onDeleteSession: deleteSession
                        )
                    }
                    .padding(.top, Spacing.compact)
                    .padding(.horizontal, Spacing.compact)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: sessionsByRepository.map(\.repository.id))
                }
            }

            ShadcnDivider()

            // Footer (empty, 20px height)
            Color.clear
                .frame(height: 20)
                .background(colors.card)
        }
        .background(colors.background)
    }
}

// MARK: - Repository Group

struct RepositoryGroup: View {
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
    let locations: SessionsByLocation
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onCreateSession: (Repository, SessionLocationType) -> Void
    var onArchiveSession: ((Session) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

    @State private var isExpanded: Bool = true
    @State private var showNewSessionDialog: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    @State private var isHoveringAdd: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repository header
            HStack(spacing: Spacing.sm) {
                Button {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.sm)

                        Image(systemName: "folder.fill")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.info)

                        Text(repository.name)
                            .font(Typography.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(colors.foreground)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // New session button (inline +)
                Button {
                    showNewSessionDialog = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: IconSize.xs, weight: .medium))
                        .foregroundStyle(isHoveringAdd ? colors.foreground : colors.mutedForeground)
                        .frame(width: IconSize.md, height: IconSize.md)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isHoveringAdd = hovering
                    }
                }
                .popover(isPresented: $showNewSessionDialog, arrowEdge: .trailing) {
                    NewSessionDialog(
                        isPresented: $showNewSessionDialog,
                        repository: repository,
                        onCreateSession: { locationType in
                            onCreateSession(repository, locationType)
                        }
                    )
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)

            // Sessions under this repository
            if isExpanded {

                // Main Directory section (always show for + button)
                MainDirectorySection(
                    repository: repository,
                    sessions: locations.mainDirectorySessions,
                    selectedSessionId: selectedSessionId,
                    onSelectSession: onSelectSession,
                    onCreateSession: { onCreateSession(repository, .mainDirectory) },
                    onArchiveSession: onArchiveSession,
                    onDeleteSession: onDeleteSession
                )

                // Worktree sections
                ForEach(locations.worktreeSessions, id: \.name) { worktreeGroup in
                    WorktreeSection(
                        name: worktreeGroup.name,
                        sessions: worktreeGroup.sessions,
                        selectedSessionId: selectedSessionId,
                        onSelectSession: onSelectSession,
                        onArchiveSession: onArchiveSession,
                        onDeleteSession: onDeleteSession
                    )
                }
            }
        }
    }
}

// MARK: - Main Directory Section

struct MainDirectorySection: View {
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
    let sessions: [Session]
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onCreateSession: () -> Void
    var onArchiveSession: ((Session) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

    @State private var isExpanded: Bool = true
    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: Spacing.sm) {
                Button {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.xs)

                        Image(systemName: "house.fill")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(colors.mutedForeground)

                        Text("Main Directory")
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // New session button (inline +)
                Button {
                    onCreateSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(isHoveringAdd ? colors.foreground : colors.mutedForeground)
                        .frame(width: IconSize.sm, height: IconSize.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isHoveringAdd = hovering
                    }
                }
            }
            .padding(.leading, Spacing.xl)
            .padding(.trailing, Spacing.md)
            .padding(.vertical, Spacing.xs)

            // Sessions
            if isExpanded {
                ForEach(sessions) { session in
                    SessionRowInGroup(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        onSelect: { onSelectSession(session) },
                        onArchive: onArchiveSession != nil ? { onArchiveSession?(session) } : nil,
                        onDelete: onDeleteSession != nil ? { onDeleteSession?(session) } : nil,
                        indentLevel: 2
                    )
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: sessions.map(\.id))
            }
        }
    }
}

// MARK: - Worktree Section

struct WorktreeSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let name: String
    let sessions: [Session]
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onArchiveSession: ((Session) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

    @State private var isExpanded: Bool = true

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: Duration.fast)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: IconSize.xs)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.success)

                    Text(name)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }
                .padding(.leading, Spacing.xl)
                .padding(.trailing, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Sessions
            if isExpanded {
                ForEach(sessions) { session in
                    SessionRowInGroup(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        onSelect: { onSelectSession(session) },
                        onArchive: onArchiveSession != nil ? { onArchiveSession?(session) } : nil,
                        onDelete: onDeleteSession != nil ? { onDeleteSession?(session) } : nil,
                        indentLevel: 2
                    )
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: sessions.map(\.id))
            }
        }
    }
}

// MARK: - Session Row In Group (simplified, no binding needed)

struct SessionRowInGroup: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    let session: Session
    let isSelected: Bool
    var onSelect: () -> Void
    var onArchive: (() -> Void)?
    var onDelete: (() -> Void)?
    var indentLevel: Int = 1  // 1 = under repository, 2 = under section (main dir / worktree)

    @State private var gitStatus: DaemonGitStatus?
    @State private var isHovered = false
    @State private var showArchiveConfirmation = false
    @State private var showDeleteConfirmation = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Calculate leading padding based on indent level
    private var leadingPadding: CGFloat {
        switch indentLevel {
        case 1: return Spacing.xl
        case 2: return Spacing.xl + Spacing.lg
        default: return Spacing.xl + (CGFloat(indentLevel - 1) * Spacing.lg)
        }
    }

    /// Check if session is actively running (Claude streaming)
    private var isSessionActive: Bool {
        appState.sessionStateManager.stateIfExists(for: session.id)?.claudeRunning ?? false
    }

    /// Get the working path for this session (worktree path or repo path)
    private var workingPath: String? {
        // If session is a worktree, use its worktree path
        if session.isWorktree, let worktreePath = session.worktreePath {
            return worktreePath
        }

        // Otherwise use the repository path
        return appState.repositories.first(where: { $0.id == session.repositoryId })?.path
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Workspace icon - morphs to loader when session is active
                SessionIcon(isActive: isSessionActive, size: IconSize.sm)

                // Session title
                Text(session.displayTitle)
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)

                Spacer()

                // Clean/dirty indicator
                if let status = gitStatus {
                    Circle()
                        .fill(status.isClean ? colors.success : colors.warning)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.leading, leadingPadding)
            .padding(.trailing, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
        .task {
            await loadGitStatus()
        }
        .contextMenu {
            Button {
                showArchiveConfirmation = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Archive Session?",
            isPresented: $showArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive") {
                onArchive?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This session will be moved to the archived section.")
        }
        .confirmationDialog(
            "Delete Session?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All messages in this session will be permanently deleted.")
        }
    }

    private func loadGitStatus() async {
        guard let path = workingPath else { return }

        do {
            gitStatus = try await appState.daemonClient.getGitStatus(path: path)
        } catch {
            gitStatus = nil
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    let session: Session
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var gitStatus: DaemonGitStatus?
    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Check if session is actively running (Claude streaming)
    private var isSessionActive: Bool {
        appState.sessionStateManager.stateIfExists(for: session.id)?.claudeRunning ?? false
    }

    /// Get the working path for this session (worktree path or repo path)
    private var workingPath: String? {
        // If session is a worktree, use its worktree path
        if session.isWorktree, let worktreePath = session.worktreePath {
            return worktreePath
        }

        // Otherwise use the repository path
        return appState.repositories.first(where: { $0.id == session.repositoryId })?.path
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Workspace icon - morphs to loader when session is active
                SessionIcon(isActive: isSessionActive, size: IconSize.sm)

                // Session title
                Text(session.displayTitle)
                    .font(Typography.bodySmall)
                    .fontWeight(.medium)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)

                Spacer()

                // Clean/dirty indicator
                if let status = gitStatus {
                    Circle()
                        .fill(status.isClean ? colors.success : colors.warning)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
        .task {
            await loadGitStatus()
        }
    }

    private func loadGitStatus() async {
        guard let path = workingPath else { return }

        do {
            gitStatus = try await appState.daemonClient.getGitStatus(path: path)
        } catch {
            gitStatus = nil
        }
    }
}

#Preview {
    WorkspacesSidebar(
        onOpenSettings: {},
        onAddRepository: {},
        onCreateSessionForRepository: { _, _ in }
    )
    .environment(AppState())
    .frame(width: 280, height: 600)
}
