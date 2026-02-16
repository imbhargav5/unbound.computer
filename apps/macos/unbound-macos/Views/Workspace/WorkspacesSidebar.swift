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
    var onRequestRemoveRepository: (Repository) -> Void

    @State private var showKeyboardShortcuts = false

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
            // Machine name header (top bar with fixed 64px height)
            SidebarHeader(
                title: Host.current().localizedName ?? "My Mac",
                onOpenKeyboardShortcuts: {
                    showKeyboardShortcuts = true
                },
                onOpenSettings: onOpenSettings,
                onToggleSidebar: {
                    withAnimation(.easeOut(duration: Duration.fast)) {
                        appState.localSettings.leftSidebarVisible = false
                    }
                }
            )

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
                                    appState.selectSession(session.id)
                                },
                                onCreateSession: onCreateSessionForRepository,
                                onRequestRemoveRepository: { repository in
                                    onRequestRemoveRepository(repository)
                                },
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
        .overlay {
            if showKeyboardShortcuts {
                KeyboardShortcutsOverlay(isPresented: $showKeyboardShortcuts)
            }
        }
        .animation(.easeInOut(duration: Duration.fast), value: showKeyboardShortcuts)
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
    var onRequestRemoveRepository: ((Repository) -> Void)?
    var onArchiveSession: ((Session) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

    @State private var isExpanded: Bool = true
    @State private var showNewSessionDialog: Bool = false
    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// All sessions flat for counting
    private var allSessions: [Session] {
        locations.mainDirectorySessions + locations.worktreeSessions.flatMap { $0.sessions }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repository header row
            HStack(spacing: Spacing.xs) {
                Button {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: 10)

                        Image(systemName: "terminal")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.primary)

                        Text(repository.name)
                            .font(Typography.sidebarProject)
                            .foregroundStyle(colors.foreground.opacity(0.9))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // Session count badge - amber styling
                if !allSessions.isEmpty {
                    Text("\(allSessions.count)")
                        .font(Typography.sidebarMeta)
                        .foregroundStyle(colors.primary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(colors.accentAmberSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .stroke(colors.accentAmberBorder, lineWidth: BorderWidth.default)
                        )
                }

                // New session button
                Button {
                    showNewSessionDialog = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isHoveringAdd ? colors.foreground : colors.mutedForeground)
                        .frame(width: IconSize.sm, height: IconSize.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringAdd = hovering
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
            .padding(.horizontal, Spacing.md)
            .frame(height: 36)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    onRequestRemoveRepository?(repository)
                } label: {
                    Label("Remove Repository...", systemImage: "trash")
                }
            }

            // Expanded content - directory sections
            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Main Directory section
                    if !locations.mainDirectorySessions.isEmpty {
                        MainDirectorySection(
                            sessions: locations.mainDirectorySessions,
                            selectedSessionId: selectedSessionId,
                            onSelectSession: onSelectSession,
                            onCreateSession: { onCreateSession(repository, .mainDirectory) },
                            onArchiveSession: onArchiveSession,
                            onDeleteSession: onDeleteSession
                        )
                    }

                    // Worktree sections
                    ForEach(locations.worktreeSessions, id: \.name) { worktree in
                        WorktreeSection(
                            name: worktree.name,
                            sessions: worktree.sessions,
                            selectedSessionId: selectedSessionId,
                            onSelectSession: onSelectSession,
                            onCreateSession: { onCreateSession(repository, .worktree) },
                            onArchiveSession: onArchiveSession,
                            onDeleteSession: onDeleteSession
                        )
                    }
                }
                .padding(.leading, Spacing.md)
            }

            // Light divider after each repository
            ShadcnDivider()
                .padding(.top, Spacing.xs)
        }
    }
}

// MARK: - Main Directory Section

/// Shows the "main" label and its sessions with flat list styling
struct MainDirectorySection: View {
    @Environment(\.colorScheme) private var colorScheme

    let sessions: [Session]
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onCreateSession: (() -> Void)?
    var onArchiveSession: ((Session) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header row
            HStack(spacing: Spacing.sm) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.gray525)

                Text("main")
                    .font(Typography.caption)
                    .foregroundStyle(colors.sidebarMeta)

                Spacer()

                // New session button
                if let onCreateSession = onCreateSession {
                    Button(action: onCreateSession) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isHoveringAdd ? colors.foreground : colors.gray404)
                            .frame(width: IconSize.xs, height: IconSize.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringAdd = hovering
                    }
                }
            }
            .padding(.leading, 28)
            .padding(.trailing, Spacing.md)
            .frame(height: LayoutMetrics.sidebarRowHeight)

            // Sessions always visible
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(sessions) { session in
                    SessionRow(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        onSelect: { onSelectSession(session) },
                        onArchive: onArchiveSession != nil ? { onArchiveSession?(session) } : nil,
                        onDelete: onDeleteSession != nil ? { onDeleteSession?(session) } : nil
                    )
                }
            }
            .padding(.top, Spacing.xxs)
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.xs + Spacing.xxs)
        }
    }
}

// MARK: - Worktree Section

/// Shows a worktree name label and its sessions with flat list styling
struct WorktreeSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let name: String
    let sessions: [Session]
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onCreateSession: (() -> Void)?
    var onArchiveSession: ((Session) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header row
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.gray525)

                Text(name.lowercased())
                    .font(Typography.caption)
                    .foregroundStyle(colors.sidebarMeta)
                    .lineLimit(1)

                Spacer()

                // New session button
                if let onCreateSession = onCreateSession {
                    Button(action: onCreateSession) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isHoveringAdd ? colors.foreground : colors.gray404)
                            .frame(width: IconSize.xs, height: IconSize.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringAdd = hovering
                    }
                }
            }
            .padding(.leading, 28)
            .padding(.trailing, Spacing.md)
            .frame(height: LayoutMetrics.sidebarRowHeight)

            // Sessions always visible
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(sessions) { session in
                    SessionRow(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        onSelect: { onSelectSession(session) },
                        onArchive: onArchiveSession != nil ? { onArchiveSession?(session) } : nil,
                        onDelete: onDeleteSession != nil ? { onDeleteSession?(session) } : nil
                    )
                }
            }
            .padding(.top, Spacing.xxs)
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.xs + Spacing.xxs)
        }
    }
}

// MARK: - Session Row

/// A session row with icon and flat list styling
struct SessionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: Session
    let isSelected: Bool
    var onSelect: () -> Void
    var onArchive: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var isHovered = false
    @State private var showArchiveConfirmation = false
    @State private var showDeleteConfirmation = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "message.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? colors.primary : colors.gray525)

                Text(session.displayTitle)
                    .font(Typography.caption)
                    .foregroundStyle(isSelected ? colors.sidebarText : colors.sidebarMeta)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.leading, 24)
            .padding(.trailing, Spacing.sm)
            .frame(height: LayoutMetrics.sidebarRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(isSelected ? colors.hoverBackground : (isHovered ? colors.hoverBackground : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(isSelected ? colors.selectionBorder : Color.clear, lineWidth: BorderWidth.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                showArchiveConfirmation = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Divider()

            Button {
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
            Button("Delete") {
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All messages in this session will be permanently deleted.")
        }
    }
}

#Preview("With Repos & Sessions") {
    WorkspacesSidebar(
        onOpenSettings: {},
        onAddRepository: {},
        onCreateSessionForRepository: { _, _ in },
        onRequestRemoveRepository: { _ in }
    )
    .environment(AppState.preview())
    .frame(width: 168, height: 600)
}

#Preview("Empty") {
    WorkspacesSidebar(
        onOpenSettings: {},
        onAddRepository: {},
        onCreateSessionForRepository: { _, _ in },
        onRequestRemoveRepository: { _ in }
    )
    .environment(AppState())
    .frame(width: 168, height: 600)
}
