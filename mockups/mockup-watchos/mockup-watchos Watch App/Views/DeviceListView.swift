//
//  DeviceListView.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct DeviceListView: View {
    @State private var devices = WatchMockData.devices

    var onlineDevices: [WatchDevice] {
        devices.filter { $0.status != .offline }
    }

    var offlineDevices: [WatchDevice] {
        devices.filter { $0.status == .offline }
    }

    var body: some View {
        NavigationStack {
            List {
                if !onlineDevices.isEmpty {
                    Section {
                        ForEach(onlineDevices) { device in
                            DeviceRowView(device: device)
                        }
                    } header: {
                        Label("Online", systemImage: "wifi")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }

                if !offlineDevices.isEmpty {
                    Section {
                        ForEach(offlineDevices) { device in
                            DeviceRowView(device: device)
                        }
                    } header: {
                        Label("Offline", systemImage: "wifi.slash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.carousel)
            .navigationTitle("Devices")
        }
    }
}

#Preview("Device List") {
    DeviceListView()
}
