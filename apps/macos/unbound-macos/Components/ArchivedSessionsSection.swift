//
//  ArchivedSessionsSection.swift
//  unbound-macos
//
//  Collapsible section for archived sessions in the sidebar.
//  Shows archived sessions grouped by repository with restore/delete actions.
//

import SwiftUI

// MARK: - Archived Sessions Section

struct ArchivedSessionsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    var onRestoreSession: (Session) -> Void
    var onDeleteSession: (Session) -> Void

    @State private var isExpanded: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Archived sessions (from daemon - TODO: implement archive status)
    private var archivedSessions: [Session] {
        // TODO: Filter by archived status when daemon supports it
        []
    }

    /// Group archived sessions by their parent repository
    private var archivedSessionsByRepository: [(repository: Repository, sessions: [Session])] {
        let repositories = appState.repositories
        return repositories.compactMap { repository in
            let repositorySessions = archivedSessions.filter { $0.repositoryId == repository.id }
            guard !repositorySessions.isEmpty else { return nil }
            return (repository: repository, sessions: repositorySessions)
        }
    }

    var body: some View {
        if !archivedSessions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Archived header (collapsible)
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

                        Image(systemName: "archivebox")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)

                        Text("Archived")
                            .font(Typography.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(colors.mutedForeground)

                        Spacer()

                        Text("\(archivedSessions.count)")
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Archived sessions grouped by repository
                if isExpanded {
                    ForEach(archivedSessionsByRepository, id: \.repository.id) { group in
                        ArchivedRepositoryGroup(
                            repository: group.repository,
                            sessions: group.sessions,
                            onRestoreSession: onRestoreSession,
                            onDeleteSession: onDeleteSession
                        )
                    }
                }
            }
            .padding(.top, Spacing.sm)
        }
    }
}

// MARK: - Archived Repository Group

struct ArchivedRepositoryGroup: View {
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
    let sessions: [Session]
    var onRestoreSession: (Session) -> Void
    var onDeleteSession: (Session) -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repository label (smaller, muted)
            HStack(spacing: Spacing.sm) {
                Image(systemName: "folder")
                    .font(.system(size: IconSize.xs))
                    .foregroundStyle(colors.mutedForeground.opacity(0.7))

                Text(repository.name)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
            }
            .padding(.leading, Spacing.xl)
            .padding(.trailing, Spacing.md)
            .padding(.vertical, Spacing.xs)

            // Archived sessions
            ForEach(sessions) { session in
                ArchivedSessionRow(
                    session: session,
                    onRestore: { onRestoreSession(session) },
                    onDelete: { onDeleteSession(session) }
                )
            }
        }
    }
}

// MARK: - Archived Session Row

struct ArchivedSessionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: Session
    var onRestore: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @State private var showRestoreConfirmation = false
    @State private var showDeleteConfirmation = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Format the last accessed date as relative time
    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.lastAccessed, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Archive icon
            Image(systemName: "archivebox")
                .font(.system(size: IconSize.sm))
                .foregroundStyle(colors.mutedForeground.opacity(0.6))

            // Session title and date
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)

                Text(relativeDate)
                    .font(Typography.micro)
                    .foregroundStyle(colors.mutedForeground.opacity(0.7))
            }

            Spacer()
        }
        .padding(.leading, Spacing.xl)
        .padding(.trailing, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .fullRowHitTarget()
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(isHovered ? colors.muted.opacity(0.5) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                showRestoreConfirmation = true
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }

            Divider()

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Restore Session?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore") {
                onRestore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This session will be moved back to the active sessions list.")
        }
        .confirmationDialog(
            "Delete Session Permanently?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete") {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All messages in this session will be permanently deleted.")
        }
    }
}

#if DEBUG

#Preview {
    ArchivedSessionsSection(
        onRestoreSession: { _ in },
        onDeleteSession: { _ in }
    )
    .environment(AppState())
    .frame(width: 280)
}

#endif
