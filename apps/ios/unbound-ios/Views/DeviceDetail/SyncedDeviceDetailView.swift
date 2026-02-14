import SwiftUI
import Logging

private let logger = Logger(label: "app.ui")

struct SyncedDeviceDetailView: View {
    let device: SyncedDevice

    @Environment(\.navigationManager) private var navigationManager

    private let syncedDataService = SyncedDataService.shared

    @State private var expandedRepoIds: Set<UUID> = []
    @State private var hasInitialized = false

    /// Repositories that have sessions belonging to this device
    private var deviceRepositories: [SyncedRepository] {
        syncedDataService.repositories.filter { repo in
            !sessionsForRepo(repo.id).isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                // Compact device header
                deviceHeader
                capabilitiesSection

                // Repository groups with sessions
                if deviceRepositories.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "No Repositories",
                        message: "No sessions found on this device."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                        ForEach(deviceRepositories) { repo in
                            SyncedRepositoryGroupView(
                                repository: repo,
                                sessions: sessionsForRepo(repo.id),
                                isExpanded: expandedBinding(for: repo.id),
                                onSessionTap: { session in
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
        .background(Color.black)
        .preferredColorScheme(.dark)
        .navigationTitle(device.hostname ?? device.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if !hasInitialized {
                // Expand all repos by default
                expandedRepoIds = Set(deviceRepositories.map(\.id))
                hasInitialized = true
            }
        }
    }

    // MARK: - Compact Device Header

    private var deviceHeader: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Device icon (compact: 40pt)
            ZStack {
                Circle()
                    .fill(AppTheme.amberAccent.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: device.deviceType.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.amberAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceType.displayName)
                    .font(Typography.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)

                if let hostname = device.hostname {
                    Text(hostname)
                        .font(Typography.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                HStack(spacing: AppTheme.spacingS) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(device.status == .online ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(device.status.displayName)
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    if let lastSeen = device.lastSeenAt {
                        Text("· \(lastSeen.formatted(.relative(presentation: .named)))")
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(AppTheme.spacingM)
        .thinBorderCard()
        .padding(.horizontal, AppTheme.spacingM)
    }

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            Text("Capabilities")
                .font(Typography.subheadline)
                .foregroundStyle(AppTheme.textPrimary)

            if let cli = device.capabilities?.cli {
                capabilityRow(title: "Claude", tool: cli.claude)
                if let models = cli.claude?.models, !models.isEmpty {
                    Text("Models: \(models.joined(separator: ", "))")
                        .font(Typography.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }
                capabilityRow(title: "GitHub CLI", tool: cli.gh)
                capabilityRow(title: "Codex", tool: cli.codex)
                capabilityRow(title: "Ollama", tool: cli.ollama)
            } else {
                Text("Not reported yet")
                    .font(Typography.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(AppTheme.spacingM)
        .thinBorderCard()
        .padding(.horizontal, AppTheme.spacingM)
    }

    private func capabilityRow(
        title: String,
        tool: DeviceCapabilities.ToolCapabilities?
    ) -> some View {
        let statusText = tool.map { $0.installed ? "Installed" : "Not installed" } ?? "Unknown"

        return HStack {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Text(statusText)
                .font(Typography.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    // MARK: - Helpers

    private func sessionsForRepo(_ repoId: UUID) -> [SyncedSession] {
        syncedDataService.sessions.filter { session in
            session.repositoryId == repoId && session.deviceId == device.id
        }
    }

    private func expandedBinding(for repoId: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedRepoIds.contains(repoId) },
            set: { isExpanded in
                if isExpanded {
                    expandedRepoIds.insert(repoId)
                } else {
                    expandedRepoIds.remove(repoId)
                }
            }
        )
    }
}

// MARK: - Collapsible Repository Group

struct SyncedRepositoryGroupView: View {
    let repository: SyncedRepository
    let sessions: [SyncedSession]
    @Binding var isExpanded: Bool
    let onSessionTap: (SyncedSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable header with chevron
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.spacingS) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.amberAccent)

                    Text(repository.name)
                        .font(Typography.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if !sessions.isEmpty {
                        Text("\(sessions.count)")
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                }
                .padding(AppTheme.spacingM)
            }
            .buttonStyle(.plain)

            // Collapsible session list
            if isExpanded {
                if sessions.isEmpty {
                    Text("No sessions")
                        .font(Typography.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, AppTheme.spacingM)
                        .padding(.bottom, AppTheme.spacingM)
                } else {
                    Divider()
                        .overlay(Color.white.opacity(0.1))
                        .padding(.horizontal, AppTheme.spacingM)

                    VStack(spacing: 4) {
                        ForEach(sessions) { session in
                            DeviceSessionRowView(session: session)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    onSessionTap(session)
                                }
                        }
                    }
                    .padding(.vertical, AppTheme.spacingXS)
                }
            }
        }
        .thinBorderCard()
    }
}
