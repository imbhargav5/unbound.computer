import SwiftUI
import Logging

private let logger = Logger(label: "app.ui")

struct DashboardView: View {
    @Environment(\.navigationManager) private var navigationManager

    private let syncedDataService = SyncedDataService.shared

    @State private var showSidebar = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.spacingL) {
                // Section 1: Recent Sessions
                recentSessionsSection

                // Section 2: Devices
                devicesSection
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.top, AppTheme.spacingS)
            .padding(.bottom, AppTheme.spacingXL)
        }
        .refreshable {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            await refreshData()
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    showSidebar = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }

            ToolbarItem(placement: .principal) {
                Text("Dashboard")
                    .font(Typography.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showSidebar) {
            SidebarView()
        }
    }

    // MARK: - Recent Sessions Section

    @ViewBuilder
    private var recentSessionsSection: some View {
        let recentSessions = syncedDataService.recentSessions

        if !recentSessions.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                Text("Recent Sessions")
                    .font(Typography.title3)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, AppTheme.spacingS)

                ForEach(recentSessions) { session in
                    RecentSessionCard(
                        session: session,
                        repository: syncedDataService.repository(for: session),
                        device: syncedDataService.device(for: session)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        navigationManager.navigateToSyncedSession(session)
                    }
                }
            }
        } else if syncedDataService.sessions.isEmpty {
            EmptyStateView(
                icon: "text.bubble",
                title: "No Sessions",
                message: "Connect a device running Claude Code to see your recent sessions."
            )
            .padding(.top, 60)
        }
    }

    // MARK: - Devices Section

    @ViewBuilder
    private var devicesSection: some View {
        let executorDevices = syncedDataService.executorDevices

        if !executorDevices.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                Text("Devices")
                    .font(Typography.title3)
                    .foregroundStyle(AppTheme.textPrimary)

                ForEach(executorDevices) { device in
                    SyncedDeviceRowView(device: device)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            navigationManager.navigateToSyncedDevice(device)
                        }
                }
            }
        }
    }

    // MARK: - Helpers

    private func refreshData() async {
        let syncService = PostLoginSyncService()
        await syncService.performPostLoginSync()
    }
}

// MARK: - Recent Session Card

struct RecentSessionCard: View {
    let session: SyncedSession
    let repository: SyncedRepository?
    let device: SyncedDevice?

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Status indicator
            Circle()
                .fill(session.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                // Session title
                Text(session.title)
                    .font(Typography.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                // Last active
                Text(session.lastAccessedAt.formatted(.relative(presentation: .named)))
                    .font(Typography.caption)
                    .foregroundStyle(AppTheme.textTertiary)

                // Repo + Device info
                if repository != nil || device != nil {
                    HStack(spacing: AppTheme.spacingS) {
                        if let repository {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10, weight: .medium))
                                Text(repository.name)
                                    .lineLimit(1)
                            }
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                        }

                        if repository != nil, device != nil {
                            Text("·")
                                .font(Typography.caption)
                                .foregroundStyle(AppTheme.textTertiary)
                        }

                        if let device {
                            HStack(spacing: 4) {
                                Image(systemName: device.deviceType.iconName)
                                    .font(.system(size: 10, weight: .medium))
                                Text(device.hostname ?? device.name)
                                    .lineLimit(1)
                            }
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(AppTheme.spacingM)
        .thinBorderCard(highlighted: session.isActive)
    }
}

// MARK: - Device Row View

struct SyncedDeviceRowView: View {
    let device: SyncedDevice

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            Image(systemName: device.deviceType.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.hostname ?? device.name)
                    .font(Typography.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(device.status == .online ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(device.status.displayName)
                        .font(Typography.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(AppTheme.spacingM)
        .thinBorderCard()
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigationManager) private var navigationManager
    @Environment(AuthService.self) private var authService
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        navigationManager.navigateToAccountSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .alert("Sign Out", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    Task {
                        dismiss()
                        try? await authService.signOut()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out? You'll need to sign in again to access your sessions.")
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .preferredColorScheme(.dark)
}
