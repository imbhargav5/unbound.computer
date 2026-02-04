//
//  WorkspacesSidebar.swift
//  mockup-macos
//
//  Shadcn-styled sessions sidebar.
//  Groups sessions by repository, then by location (main directory vs worktree).
//

import SwiftUI

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
    @Environment(MockAppState.self) private var appState

    var onOpenSettings: () -> Void
    var onAddRepository: () -> Void
    var onCreateSessionForRepository: (Repository, SessionLocationType) -> Void

    @State private var showKeyboardShortcuts = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    // MARK: - Computed Properties

    /// Active sessions from AppState
    private var sessions: [Session] {
        appState.sessions.values.flatMap { $0 }
    }

    /// Selected session based on selectedSessionId
    private var selectedSession: Session? {
        appState.selectedSession
    }

    /// Group sessions by repository
    private var sessionsByRepository: [(repository: Repository, locations: SessionsByLocation)] {
        let repositories = appState.repositories
        return repositories.map { repository in
            let repositorySessions = appState.sessionsForRepository(repository.id)

            // Split into main directory and worktree sessions
            let mainDirSessions = repositorySessions.filter { !$0.isWorktree }
            let worktreeSess = repositorySessions.filter { $0.isWorktree }

            // Group worktree sessions by their worktree name
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

    var body: some View {
        VStack(spacing: 0) {
            // Agents header (top bar with fixed 64px height)
            SidebarHeader(
                title: "Agents",
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
                                    appState.selectedSessionId = session.id
                                },
                                onCreateSession: onCreateSessionForRepository
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
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

// MARK: - Timeline Constants

private enum TimelineMetrics {
    /// Width of the timeline spine area (left gutter)
    static let spineAreaWidth: CGFloat = 16
    /// Horizontal offset of the spine line from left edge
    static let spineOffset: CGFloat = 6
    /// Width of the spine line
    static let spineWidth: CGFloat = 1
    /// Length of horizontal connector lines
    static let connectorLength: CGFloat = 8
    /// Vertical padding for connectors at group level
    static let groupConnectorY: CGFloat = 10
    /// Content left padding after spine area
    static let contentPadding: CGFloat = 4
}

// MARK: - Repository Group

struct RepositoryGroup: View {
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
    let locations: SessionsByLocation
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onCreateSession: (Repository, SessionLocationType) -> Void

    @State private var isExpanded: Bool = true
    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Spine color - visible but not dominant
    private var spineColor: Color {
        colors.border
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

                        Text(repository.name)
                            .font(Typography.sidebarProject)
                            .foregroundStyle(colors.foreground.opacity(0.9))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // Session count badge
                if !allSessions.isEmpty {
                    Text("\(allSessions.count)")
                        .font(Typography.sidebarMeta)
                        .foregroundStyle(colors.sidebarMeta)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(colors.muted.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }

                // New session button
                Button {
                    onCreateSession(repository, .mainDirectory)
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
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)

            // Expanded content - directories with their own spines
            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Main Directory section
                    if !locations.mainDirectorySessions.isEmpty {
                        MainDirectorySection(
                            sessions: locations.mainDirectorySessions,
                            selectedSessionId: selectedSessionId,
                            onSelectSession: onSelectSession,
                            onCreateSession: { onCreateSession(repository, .mainDirectory) },
                            spineColor: spineColor
                        )
                    }

                    // Worktree sections
                    ForEach(locations.worktreeSessions, id: \.name) { worktree in
                        WorktreeSection(
                            name: worktree.name,
                            sessions: worktree.sessions,
                            selectedSessionId: selectedSessionId,
                            onSelectSession: onSelectSession,
                            onCreateSession: { onCreateSession(repository, .newWorktree) },
                            spineColor: spineColor
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

/// Shows the "Main Directory" label and its sessions with timeline styling
struct MainDirectorySection: View {
    @Environment(\.colorScheme) private var colorScheme

    let sessions: [Session]
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onCreateSession: (() -> Void)?
    let spineColor: Color

    @State private var isExpanded: Bool = true
    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header row
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

                        Text("MAIN DIRECTORY")
                            .font(Typography.sidebarSection)
                            .foregroundStyle(colors.mutedForeground)
                            .tracking(0.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // New session button
                if let onCreateSession = onCreateSession {
                    Button(action: onCreateSession) {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(isHoveringAdd ? colors.foreground : colors.mutedForeground)
                            .frame(width: IconSize.xs, height: IconSize.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringAdd = hovering
                    }
                }
            }
            .padding(.trailing, Spacing.sm)
            .padding(.vertical, Spacing.xxs)

            // Sessions with spine (only when expanded)
            if isExpanded {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    let isLast = index == sessions.count - 1
                    TimelineSessionRow(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        isLast: isLast,
                        onSelect: { onSelectSession(session) },
                        spineColor: spineColor
                    )
                }
            }
        }
    }
}

// MARK: - Worktree Section

/// Shows a worktree name label and its sessions with timeline styling
struct WorktreeSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let name: String
    let sessions: [Session]
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onCreateSession: (() -> Void)?
    let spineColor: Color

    @State private var isExpanded: Bool = true
    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header row
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

                        Image(systemName: "folder")
                            .font(.system(size: 9))
                            .foregroundStyle(colors.mutedForeground)

                        Text(name.uppercased())
                            .font(Typography.sidebarSection)
                            .foregroundStyle(colors.mutedForeground)
                            .tracking(0.5)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // New session button
                if let onCreateSession = onCreateSession {
                    Button(action: onCreateSession) {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(isHoveringAdd ? colors.foreground : colors.mutedForeground)
                            .frame(width: IconSize.xs, height: IconSize.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringAdd = hovering
                    }
                }
            }
            .padding(.trailing, Spacing.sm)
            .padding(.vertical, Spacing.xxs)

            // Sessions with spine (only when expanded)
            if isExpanded {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    let isLast = index == sessions.count - 1
                    TimelineSessionRow(
                        session: session,
                        isSelected: selectedSessionId == session.id,
                        isLast: isLast,
                        onSelect: { onSelectSession(session) },
                        spineColor: spineColor
                    )
                }
            }
        }
    }
}

// MARK: - Timeline Session Row

/// A session row with timeline spine and horizontal connector
struct TimelineSessionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: Session
    let isSelected: Bool
    let isLast: Bool
    var onSelect: () -> Void
    let spineColor: Color

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Row height for calculating spine
    private let rowHeight: CGFloat = 28

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 0) {
                // Spine area with vertical line and horizontal connector
                ZStack(alignment: .topLeading) {
                    // Vertical spine - extends from top, full height or half for last item
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(spineColor)
                            .frame(width: TimelineMetrics.spineWidth)
                            .frame(height: isLast ? rowHeight / 2 : nil)
                            .frame(maxHeight: isLast ? nil : .infinity)
                    }
                    .padding(.leading, TimelineMetrics.spineOffset)

                    // Horizontal connector at vertical center of row
                    Rectangle()
                        .fill(spineColor)
                        .frame(width: TimelineMetrics.connectorLength, height: TimelineMetrics.spineWidth)
                        .padding(.leading, TimelineMetrics.spineOffset)
                        .padding(.top, rowHeight / 2)
                }
                .frame(width: TimelineMetrics.spineAreaWidth)

                // Session content
                HStack(spacing: Spacing.xs) {
                    // Session title
                    Text(session.displayTitle)
                        .font(Typography.sidebarItem)
                        .foregroundStyle(isSelected ? colors.foreground : colors.sidebarText)
                        .lineLimit(1)

                    Spacer()

                    // Status indicator
                    Circle()
                        .fill(colors.success)
                        .frame(width: 6, height: 6)
                }
                .padding(.leading, TimelineMetrics.contentPadding)
                .padding(.trailing, Spacing.sm)
                .frame(height: rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isSelected ? colors.accent.opacity(0.3) : (isHovered ? colors.muted.opacity(0.5) : Color.clear))
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Removed Components (No longer needed with flat timeline)
// MainDirectorySection and WorktreeSection removed - sessions now in flat list

#Preview {
    WorkspacesSidebar(
        onOpenSettings: {},
        onAddRepository: {},
        onCreateSessionForRepository: { _, _ in }
    )
    .environment(MockAppState())
    .frame(width: 168, height: 600)
}
