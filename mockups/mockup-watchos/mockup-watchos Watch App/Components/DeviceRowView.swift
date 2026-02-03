//
//  DeviceRowView.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct DeviceRowView: View {
    let device: WatchDevice

    var body: some View {
        HStack(spacing: WatchTheme.spacingM) {
            // Device icon with status
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: device.type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(device.status == .offline ? .secondary : .primary)

                DeviceStatusIndicator(status: device.status, size: 8)
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if device.activeSessionCount > 0 {
                    Text("\(device.activeSessionCount) session\(device.activeSessionCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if device.status == .offline {
                    Text("Offline")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No sessions")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, WatchTheme.spacingS)
        .opacity(device.status == .offline ? 0.6 : 1.0)
    }
}

#Preview("Device Row") {
    List {
        ForEach(WatchMockData.devices) { device in
            DeviceRowView(device: device)
        }
    }
}
