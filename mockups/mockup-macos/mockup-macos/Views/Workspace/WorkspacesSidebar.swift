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

// MARK: - Repository Group (Timeline Style)

struct RepositoryGroup: View {
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
    let locations: SessionsByLocation
    let selectedSessionId: UUID?
    var onSelectSession: (Session) -> Void
    var onCreateSession: (Repository, SessionLocationType) -> Void

    @State private var isExpanded: Bool = true

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    @State private var isHoveringAdd: Bool = false

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
            HStack(spacing: 0) {
                // Spine area with vertical line and connector
                ZStack(alignment: .topLeading) {
                    // Vertical spine (extends down if expanded)
                    if isExpanded && !allSessions.isEmpty {
                        Rectangle()
                            .fill(spineColor)
                            .frame(width: TimelineMetrics.spineWidth)
                            .padding(.leading, TimelineMetrics.spineOffset)
                            .padding(.top, TimelineMetrics.groupConnectorY)
                    }
                }
                .frame(width: TimelineMetrics.spineAreaWidth)

                // Repository header content
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
                                .font(Typography.bodySmall)
                                .fontWeight(.medium)
                                .foregroundStyle(colors.mutedForeground)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Session count badge
                    if !allSessions.isEmpty {
                        Text("\(allSessions.count)")
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
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
                .padding(.trailing, Spacing.sm)
                .padding(.vertical, Spacing.xs)
            }

            // Expanded content with timeline - Main Directory section first, then worktrees
            if isExpanded {
                // Main Directory section
                if !locations.mainDirectorySessions.isEmpty {
                    MainDirectorySection(
                        sessions: locations.mainDirectorySessions,
                        selectedSessionId: selectedSessionId,
                        onSelectSession: onSelectSession,
                        onCreateSession: { onCreateSession(repository, .mainDirectory) },
                        spineColor: spineColor,
                        isLastSection: locations.worktreeSessions.isEmpty
                    )
                }

                // Worktree sections
                ForEach(Array(locations.worktreeSessions.enumerated()), id: \.element.name) { index, worktree in
                    WorktreeSection(
                        name: worktree.name,
                        sessions: worktree.sessions,
                        selectedSessionId: selectedSessionId,
                        onSelectSession: onSelectSession,
                        onCreateSession: { onCreateSession(repository, .newWorktree) },
                        spineColor: spineColor,
                        isLastSection: index == locations.worktreeSessions.count - 1
                    )
                }
            }
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
    let isLastSection: Bool

    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Row height for section header
    private let headerHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header row
            HStack(spacing: 0) {
                // Spine area with vertical line and horizontal connector
                ZStack(alignment: .topLeading) {
                    // Vertical spine (continues down through sessions)
                    Rectangle()
                        .fill(spineColor)
                        .frame(width: TimelineMetrics.spineWidth)
                        .padding(.leading, TimelineMetrics.spineOffset)

                    // Horizontal connector to section label
                    Rectangle()
                        .fill(spineColor)
                        .frame(width: TimelineMetrics.connectorLength, height: TimelineMetrics.spineWidth)
                        .padding(.leading, TimelineMetrics.spineOffset)
                        .padding(.top, headerHeight / 2)
                }
                .frame(width: TimelineMetrics.spineAreaWidth, height: headerHeight)

                // Section label and add button
                HStack(spacing: Spacing.xs) {
                    Text("Main Directory")
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)

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
                .padding(.leading, TimelineMetrics.contentPadding)
                .padding(.trailing, Spacing.sm)
            }

            // Sessions in this section
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                let isLastInSection = index == sessions.count - 1
                TimelineSessionRow(
                    session: session,
                    isSelected: selectedSessionId == session.id,
                    isLast: isLastInSection && isLastSection,
                    continueSpine: !(isLastInSection && isLastSection),
                    onSelect: { onSelectSession(session) },
                    spineColor: spineColor
                )
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
    let isLastSection: Bool

    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Row height for section header
    private let headerHeight: CGFloat = 24

    /// Extract worktree display name (e.g., "happy-giraffe-08a54f" from full path)
    private var worktreeDisplayName: String {
        name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header row
            HStack(spacing: 0) {
                // Spine area with vertical line and horizontal connector
                ZStack(alignment: .topLeading) {
                    // Vertical spine (continues down through sessions)
                    Rectangle()
                        .fill(spineColor)
                        .frame(width: TimelineMetrics.spineWidth)
                        .padding(.leading, TimelineMetrics.spineOffset)

                    // Horizontal connector to section label
                    Rectangle()
                        .fill(spineColor)
                        .frame(width: TimelineMetrics.connectorLength, height: TimelineMetrics.spineWidth)
                        .padding(.leading, TimelineMetrics.spineOffset)
                        .padding(.top, headerHeight / 2)
                }
                .frame(width: TimelineMetrics.spineAreaWidth, height: headerHeight)

                // Section label with folder icon and add button
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                        .foregroundStyle(colors.mutedForeground)

                    Text(worktreeDisplayName)
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)

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
                .padding(.leading, TimelineMetrics.contentPadding)
                .padding(.trailing, Spacing.sm)
            }

            // Sessions in this section
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                let isLastInSection = index == sessions.count - 1
                TimelineSessionRow(
                    session: session,
                    isSelected: selectedSessionId == session.id,
                    isLast: isLastInSection && isLastSection,
                    continueSpine: !(isLastInSection && isLastSection),
                    onSelect: { onSelectSession(session) },
                    spineColor: spineColor
                )
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
    var continueSpine: Bool = true
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
            HStack(spacing: 0) {
                // Spine area with vertical line and horizontal connector
                ZStack(alignment: .topLeading) {
                    // Vertical spine (full height if continuing, half height to connector if last)
                    Rectangle()
                        .fill(spineColor)
                        .frame(width: TimelineMetrics.spineWidth, height: continueSpine ? rowHeight : rowHeight / 2)
                        .padding(.leading, TimelineMetrics.spineOffset)

                    // Horizontal connector
                    Rectangle()
                        .fill(spineColor)
                        .frame(width: TimelineMetrics.connectorLength, height: TimelineMetrics.spineWidth)
                        .padding(.leading, TimelineMetrics.spineOffset)
                        .padding(.top, rowHeight / 2)
                }
                .frame(width: TimelineMetrics.spineAreaWidth, height: rowHeight)

                // Session content
                HStack(spacing: Spacing.xs) {
                    // Session title
                    Text(session.displayTitle)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)

                    Spacer()

                    // Status indicator
                    Circle()
                        .fill(colors.success)
                        .frame(width: 6, height: 6)
                }
                .padding(.leading, TimelineMetrics.contentPadding)
                .padding(.trailing, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .frame(height: rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isSelected ? colors.accent.opacity(0.3) : (isHovered ? colors.muted.opacity(0.5) : Color.clear))
                )
            }
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
    .frame(width: 280, height: 600)
}
