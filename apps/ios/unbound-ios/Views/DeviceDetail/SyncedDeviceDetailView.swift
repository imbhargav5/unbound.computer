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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let syncedDataService = SyncedDataService.shared

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad or landscape - wider cards
            return [
                GridItem(.flexible(), spacing: AppTheme.spacingM),
                GridItem(.flexible(), spacing: AppTheme.spacingM),
                GridItem(.flexible(), spacing: AppTheme.spacingM)
            ]
        } else {
            // iPhone portrait - 2 column grid
            return [
                GridItem(.flexible(), spacing: AppTheme.spacingM),
                GridItem(.flexible(), spacing: AppTheme.spacingM)
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                // Device Header Card
                deviceHeader

                // Repositories Section
                if syncedDataService.repositories.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "No Repositories",
                        message: "This device has no repositories with Claude Code sessions."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                        Text("Repositories")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, AppTheme.spacingM)

                        LazyVGrid(columns: columns, spacing: AppTheme.spacingM) {
                            ForEach(syncedDataService.repositories) { repo in
                                SyncedRepositoryCardView(
                                    repository: repo,
                                    sessionCount: syncedDataService.sessions(for: repo.id).count,
                                    isCompact: horizontalSizeClass != .regular
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingM)
                    }
                }

                // Active Sessions Section
                let activeSessions = syncedDataService.activeSessions
                if !activeSessions.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                        Text("Active Sessions")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, AppTheme.spacingM)

                        VStack(spacing: AppTheme.spacingS) {
                            ForEach(activeSessions) { session in
                                SyncedSessionRowView(
                                    session: session,
                                    repository: syncedDataService.repository(for: session)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    navigationManager.navigateToSyncedSession(session)
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingM)
                    }
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

// MARK: - Repository Card View

struct SyncedRepositoryCardView: View {
    let repository: SyncedRepository
    let sessionCount: Int
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            // Repository icon
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient.opacity(0.15))
                    .frame(width: isCompact ? 40 : 48, height: isCompact ? 40 : 48)

                Image(systemName: "folder.fill")
                    .font(.system(size: isCompact ? 18 : 22, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            Text(repository.name)
                .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacingM)
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
                Text(repository?.name ?? "Unknown Repository")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

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
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
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
