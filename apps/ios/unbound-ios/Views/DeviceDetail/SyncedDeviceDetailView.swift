//
//  SyncedDeviceDetailView.swift
//  unbound-ios
//
//  Detail view for a synced device showing its repositories and sessions.
//

import SwiftUI

struct SyncedDeviceDetailView: View {
    let device: SyncedDevice

    @Environment(\.navigationManager) private var navigationManager

    private let syncedDataService = SyncedDataService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                // Device Header Card
                deviceHeader

                // Repositories with Sessions
                if syncedDataService.repositories.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "No Repositories",
                        message: "This device has no repositories with Claude Code sessions."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                        ForEach(syncedDataService.repositories) { repo in
                            let repoSessions = syncedDataService.sessions(for: repo.id)
                            SyncedRepositoryGroupView(
                                repository: repo,
                                sessions: repoSessions,
                                onSessionTap: { session in
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    navigationManager.navigateToSyncedSession(session)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingM)
                }
            }
            .padding(.top, AppTheme.spacingM)
            .padding(.bottom, AppTheme.spacingXL)
        }
        .background(AppTheme.backgroundPrimary)
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private var deviceHeader: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Device Icon
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: device.deviceType.iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text(device.deviceType.displayName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                if let hostname = device.hostname {
                    Text(hostname)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                HStack(spacing: AppTheme.spacingM) {
                    SyncedDeviceStatusIndicator(status: device.status)

                    if let lastSeen = device.lastSeenAt {
                        Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
        .shadow(
            color: AppTheme.cardShadowColor,
            radius: AppTheme.cardShadowRadius,
            x: 0,
            y: AppTheme.cardShadowY
        )
        .padding(.horizontal, AppTheme.spacingM)
    }
}

// MARK: - Repository Group View

struct SyncedRepositoryGroupView: View {
    let repository: SyncedRepository
    let sessions: [SyncedSession]
    let onSessionTap: (SyncedSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repository header
            HStack(spacing: AppTheme.spacingS) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.accent)

                Text(repository.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                if let branch = repository.defaultBranch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(branch)
                            .font(.caption2)
                    }
                    .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .padding(AppTheme.spacingM)

            if sessions.isEmpty {
                Text("No sessions")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, AppTheme.spacingM)
                    .padding(.bottom, AppTheme.spacingM)
            } else {
                Divider()
                    .padding(.horizontal, AppTheme.spacingM)

                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        SyncedSessionRowView(
                            session: session,
                            repository: nil
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSessionTap(session)
                        }

                        if session.id != sessions.last?.id {
                            Divider()
                                .padding(.horizontal, AppTheme.spacingM)
                        }
                    }
                }
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
        .shadow(
            color: AppTheme.cardShadowColor,
            radius: AppTheme.cardShadowRadius,
            x: 0,
            y: AppTheme.cardShadowY
        )
    }
}

// MARK: - Session Row View

struct SyncedSessionRowView: View {
    let session: SyncedSession
    let repository: SyncedRepository?

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Status indicator
            Circle()
                .fill(session.isActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text("Last active \(session.lastAccessedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(AppTheme.spacingM)
    }
}

#Preview {
    NavigationStack {
        SyncedDeviceDetailView(device: SyncedDevice(
            id: UUID(),
            name: "Bhargav's MacBook Pro",
            deviceType: .macDesktop,
            hostname: "bhargavs-mbp.local",
            isActive: true,
            lastSeenAt: Date(),
            createdAt: Date()
        ))
    }
    .tint(AppTheme.accent)
}
