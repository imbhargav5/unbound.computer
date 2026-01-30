import SwiftUI

struct DeviceListView: View {
    @Environment(\.navigationManager) private var navigationManager
    @State private var searchText = ""

    private let syncedDataService = SyncedDataService.shared

    /// Filter to show only executor devices (Mac, Windows, Linux - devices that run Claude Code)
    var executorDevices: [SyncedDevice] {
        syncedDataService.executorDevices
    }

    var filteredDevices: [SyncedDevice] {
        if searchText.isEmpty {
            return executorDevices
        }
        return executorDevices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.hostname?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.spacingM) {
                if filteredDevices.isEmpty {
                    EmptyStateView(
                        icon: searchText.isEmpty ? "laptopcomputer" : "magnifyingglass",
                        title: searchText.isEmpty ? "No Devices" : "No Results",
                        message: searchText.isEmpty
                            ? "Connect to a device running Claude Code to get started."
                            : "No devices match '\(searchText)'"
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(filteredDevices) { device in
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
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.top, AppTheme.spacingS)
        }
        .background(AppTheme.backgroundPrimary)
        .navigationTitle("Devices")
        .searchable(text: $searchText, prompt: "Search devices")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    navigationManager.navigateToAccountSettings()
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .refreshable {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            // Refresh devices from Supabase
            await refreshDevices()
        }
    }

    private func refreshDevices() async {
        let syncService = PostLoginSyncService()
        await syncService.performPostLoginSync()
    }
}

#Preview {
    NavigationStack {
        DeviceListView()
    }
    .tint(AppTheme.accent)
}
