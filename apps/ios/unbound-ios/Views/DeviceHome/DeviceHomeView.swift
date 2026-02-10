import SwiftUI
import Logging

private let logger = Logger(label: "app.ui")

struct DeviceHomeView: View {
    @Environment(\.navigationManager) private var navigationManager

    private let syncedDataService = SyncedDataService.shared

    @State private var selectedDevice: SyncedDevice?
    @State private var expandedRepoIds: Set<UUID> = []
    @State private var showDevicePicker = false
    @State private var hasInitialized = false

    private var executorDevices: [SyncedDevice] {
        syncedDataService.executorDevices
    }

    var body: some View {
        VStack(spacing: 0) {
            // Device picker header
            DevicePickerHeader(
                device: selectedDevice,
                showDevicePicker: $showDevicePicker
            )

            // Main content
            ScrollView {
                LazyVStack(spacing: AppTheme.spacingM) {
                    if syncedDataService.repositories.isEmpty {
                        EmptyStateView(
                            icon: "folder",
                            title: "No Repositories",
                            message: "Connect a device running Claude Code to see repositories and sessions."
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(syncedDataService.repositories) { repo in
                            let sessions = syncedDataService.sessions(for: repo.id)
                            RepositoryCardView(
                                repository: repo,
                                sessions: sessions,
                                isExpanded: expandedBinding(for: repo.id),
                                onSessionTap: { session in
                                    navigationManager.navigateToSyncedSession(session)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, AppTheme.spacingM)
                .padding(.top, AppTheme.spacingS)
                .padding(.bottom, 80)
            }
            .refreshable {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                await refreshData()
            }

            Spacer(minLength: 0)

            // Bottom settings bar
            bottomBar
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDevicePicker) {
            devicePickerSheet
        }
        .onAppear {
            if !hasInitialized {
                initializeState()
                hasInitialized = true
            }
        }
        .onChange(of: executorDevices) { _, newDevices in
            // Auto-select first online executor device if current selection goes away
            if selectedDevice == nil || !newDevices.contains(where: { $0.id == selectedDevice?.id }) {
                selectedDevice = newDevices.first(where: { $0.status == .online }) ?? newDevices.first
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                navigationManager.navigateToAccountSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, AppTheme.spacingM)
        .padding(.bottom, AppTheme.spacingXS)
    }

    // MARK: - Device Picker Sheet

    private var devicePickerSheet: some View {
        NavigationStack {
            List(executorDevices) { device in
                Button {
                    selectedDevice = device
                    showDevicePicker = false
                } label: {
                    HStack(spacing: AppTheme.spacingM) {
                        Image(systemName: device.deviceType.iconName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.hostname ?? device.name)
                                .font(Typography.body)
                                .foregroundStyle(AppTheme.textPrimary)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(device.status == .online ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(device.status.displayName)
                                    .font(Typography.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }

                        Spacer()

                        if device.id == selectedDevice?.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.amberAccent)
                        }
                    }
                    .padding(.vertical, AppTheme.spacingXS)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showDevicePicker = false
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    private func initializeState() {
        // Default select first online executor device
        selectedDevice = executorDevices.first(where: { $0.status == .online }) ?? executorDevices.first

        // Expand all repos by default
        expandedRepoIds = Set(syncedDataService.repositories.map(\.id))
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

    private func refreshData() async {
        let syncService = PostLoginSyncService()
        await syncService.performPostLoginSync()
    }
}

#Preview {
    NavigationStack {
        DeviceHomeView()
    }
    .preferredColorScheme(.dark)
}
