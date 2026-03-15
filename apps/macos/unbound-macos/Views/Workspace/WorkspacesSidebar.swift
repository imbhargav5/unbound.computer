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
    var onCreateTerminalTab: (Session) -> Void = { _ in }

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

    /// Rename a session.
    private func renameSession(_ session: Session, title: String) {
        Task {
            do {
                _ = try await appState.renameSession(
                    session.id,
                    repositoryId: session.repositoryId,
                    title: title
                )
            } catch {
                logger.error("Failed to rename session: \(error)")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar header (top bar with fixed 64px height)
            SidebarHeader(
                title: "Workspaces",
                onOpenKeyboardShortcuts: {
                    showKeyboardShortcuts = true
                },
                onOpenSettings: onOpenSettings
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
                                    appState.selectSession(session.id, source: .sidebar)
                                },
                                onCreateSession: onCreateSessionForRepository,
                                onRequestRemoveRepository: { repository in
                                    onRequestRemoveRepository(repository)
                                },
                                onCreateTerminalTab: onCreateTerminalTab,
                                onArchiveSession: archiveSession,
                                onRenameSession: renameSession,
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
                    .padding(.horizontal, LayoutMetrics.sidebarInset)
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
    var onCreateTerminalTab: ((Session) -> Void)?
    var onArchiveSession: ((Session) -> Void)?
    var onRenameSession: ((Session, String) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

    @State private var isExpanded: Bool = true
    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// All sessions flat for counting
    private var allSessions: [Session] {
        locations.mainDirectorySessions + locations.worktreeSessions.flatMap { $0.sessions }
    }

    /// Highlights only the repository that owns the selected conversation session.
    private var hasSelectedSession: Bool {
        guard let selectedSessionId else { return false }
        return allSessions.contains { $0.id == selectedSessionId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repository header row
            ZStack(alignment: .trailing) {
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
                            .foregroundStyle(hasSelectedSession ? colors.primary : colors.foreground)

                        Text(repository.name)
                            .font(Typography.sidebarProject)
                            .foregroundStyle(colors.foreground.opacity(0.9))

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
                    }
                    .padding(.trailing, Spacing.xs + IconSize.sm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fullRowHitTarget()
            }
            .padding(.horizontal, LayoutMetrics.sidebarInset)
            .frame(height: 36)
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
                            onCreateTerminalTab: onCreateTerminalTab,
                            onArchiveSession: onArchiveSession,
                            onRenameSession: onRenameSession,
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
                            onCreateTerminalTab: onCreateTerminalTab,
                            onArchiveSession: onArchiveSession,
                            onRenameSession: onRenameSession,
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
    var onCreateTerminalTab: ((Session) -> Void)?
    var onArchiveSession: ((Session) -> Void)?
    var onRenameSession: ((Session, String) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

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
            }
            .padding(.leading, LayoutMetrics.sidebarInset)
            .padding(.trailing, Spacing.md)
            .frame(height: LayoutMetrics.sidebarRowHeight)

            // Sessions always visible
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(sessions) { session in
                    SessionRow(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        onSelect: { onSelectSession(session) },
                        onCreateTerminalTab: onCreateTerminalTab != nil ? { onCreateTerminalTab?(session) } : nil,
                        onArchive: onArchiveSession != nil ? { onArchiveSession?(session) } : nil,
                        onRename: onRenameSession != nil ? { newTitle in
                            onRenameSession?(session, newTitle)
                        } : nil,
                        onDelete: onDeleteSession != nil ? { onDeleteSession?(session) } : nil
                    )
                }
            }
            .padding(.top, Spacing.xxs)
            .padding(.leading, LayoutMetrics.sidebarInset)
            .padding(.trailing, Spacing.sm)
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
    var onCreateTerminalTab: ((Session) -> Void)?
    var onArchiveSession: ((Session) -> Void)?
    var onRenameSession: ((Session, String) -> Void)?
    var onDeleteSession: ((Session) -> Void)?

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
            }
            .padding(.leading, LayoutMetrics.sidebarInset)
            .padding(.trailing, Spacing.md)
            .frame(height: LayoutMetrics.sidebarRowHeight)

            // Sessions always visible
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(sessions) { session in
                    SessionRow(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        onSelect: { onSelectSession(session) },
                        onCreateTerminalTab: onCreateTerminalTab != nil ? { onCreateTerminalTab?(session) } : nil,
                        onArchive: onArchiveSession != nil ? { onArchiveSession?(session) } : nil,
                        onRename: onRenameSession != nil ? { newTitle in
                            onRenameSession?(session, newTitle)
                        } : nil,
                        onDelete: onDeleteSession != nil ? { onDeleteSession?(session) } : nil
                    )
                }
            }
            .padding(.top, Spacing.xxs)
            .padding(.leading, LayoutMetrics.sidebarInset)
            .padding(.trailing, Spacing.sm)
            .padding(.bottom, Spacing.xs + Spacing.xxs)
        }
    }
}

// MARK: - Session Row

/// A session row with icon and flat list styling
struct SessionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    let session: Session
    let isSelected: Bool
    var onSelect: () -> Void
    var onCreateTerminalTab: (() -> Void)?
    var onArchive: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onDelete: (() -> Void)?

    @State private var isHovered = false
    @State private var showArchiveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showRenameDialog = false
    @State private var renameTitle = ""

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                Image("bot")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(isSelected ? colors.primary : colors.gray525)
                .frame(width: 12, height: 12)

                Text(session.displayTitle)
                    .font(Typography.caption)
                    .foregroundStyle(isSelected ? colors.sidebarText : colors.sidebarMeta)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.leading, LayoutMetrics.sidebarInset)
            .padding(.trailing, Spacing.sm)
            .frame(height: LayoutMetrics.sidebarRowHeight)
            .fullWidthRow()
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(isSelected ? colors.hoverBackground : (isHovered ? colors.hoverBackground : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(isSelected ? colors.selectionBorder : Color.clear, lineWidth: BorderWidth.hairline)
            )
        }
        .buttonStyle(.plain)
        .fullRowHitTarget()
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if onRename != nil {
                Button {
                    renameTitle = session.displayTitle
                    showRenameDialog = true
                } label: {
                    Label("Rename...", systemImage: "pencil")
                }

                Divider()
            }

            if onCreateTerminalTab != nil {
                Button {
                    onCreateTerminalTab?()
                } label: {
                    Label("New Terminal Tab", systemImage: "terminal")
                }

                Divider()
            }

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
        .sheet(isPresented: $showArchiveConfirmation) {
            ArchiveSessionSheet {
                onArchive?()
            }
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            DeleteSessionSheet {
                onDelete?()
            }
        }
        .sheet(isPresented: $showRenameDialog) {
            RenameSessionSheet(initialTitle: renameTitle) { newTitle in
                onRename?(newTitle)
            }
        }
    }
}

private struct ArchiveSessionSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let onArchive: () -> Void

    private var colors: ThemeColors { ThemeColors(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "archivebox")
                    .font(.system(size: IconSize.lg, weight: .semibold))
                    .foregroundStyle(colors.warning)
                Text("Archive Session?")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)
                Spacer()
            }

            Text("This session will be moved to the archived section.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)

            HStack(spacing: Spacing.sm) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonSecondary(size: .sm)
                Button("Archive") {
                    onArchive()
                    dismiss()
                }
                .buttonPrimary(size: .sm)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 320)
        .background(colors.card)
    }
}

private struct DeleteSessionSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let onDelete: () -> Void

    private var colors: ThemeColors { ThemeColors(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "trash")
                    .font(.system(size: IconSize.lg, weight: .semibold))
                    .foregroundStyle(colors.destructive)
                Text("Delete Session?")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)
                Spacer()
            }

            Text("This action cannot be undone. All messages in this session will be permanently deleted.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)

            HStack(spacing: Spacing.sm) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonSecondary(size: .sm)
                Button("Delete") {
                    onDelete()
                    dismiss()
                }
                .buttonDestructive(size: .sm)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 360)
        .background(colors.card)
    }
}

private struct RenameSessionSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @FocusState private var isTitleFocused: Bool
    let onSave: (String) -> Void

    private var colors: ThemeColors { ThemeColors(colorScheme) }

    init(initialTitle: String, onSave: @escaping (String) -> Void) {
        _title = State(initialValue: initialTitle)
        self.onSave = onSave
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "pencil")
                    .font(.system(size: IconSize.lg, weight: .semibold))
                    .foregroundStyle(colors.primary)
                Text("Rename Session")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)
                Spacer()
            }

            ShadcnDivider()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Session title")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                ShadcnTextField("Session title", text: $title, variant: .filled)
                    .focused($isTitleFocused)
                    .onSubmit { handleSave() }
            }

            HStack(spacing: Spacing.sm) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonSecondary(size: .sm)
                Button("Save") { handleSave() }
                    .buttonPrimary(size: .sm)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 360)
        .background(colors.card)
        .onAppear {
            Task { @MainActor in
                isTitleFocused = true
            }
        }
    }

    private func handleSave() {
        let newTitle = trimmedTitle
        guard !newTitle.isEmpty else { return }
        onSave(newTitle)
        dismiss()
    }
}

#if DEBUG

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

#endif
