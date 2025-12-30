import SwiftUI

struct DeviceListView: View {
    @Environment(\.navigationManager) private var navigationManager
    @State private var searchText = ""
    @State private var devices = MockData.devices

    var filteredDevices: [Device] {
        if searchText.isEmpty {
            return devices
        }
        return devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.hostname.localizedCaseInsensitiveContains(searchText)
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
                        DeviceRowView(device: device)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                navigationManager.navigateToDevice(device)
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
            // Simulate refresh
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            try? await Task.sleep(for: .seconds(1))
            devices = MockData.devices
        }
    }
}

#Preview {
    NavigationStack {
        DeviceListView()
    }
    .tint(AppTheme.accent)
}
