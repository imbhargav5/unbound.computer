//
//  StatusBadge.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct StatusBadge: View {
    let status: WatchSessionStatus
    var showLabel: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: WatchTheme.spacingS) {
            Image(systemName: status.icon)
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(status.color)

            if showLabel {
                Text(compact ? status.shortLabel : status.label)
                    .font(.system(size: compact ? 10 : 12, weight: .medium))
                    .foregroundStyle(status.color)
            }
        }
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 2 : 3)
        .background(status.color.opacity(0.2))
        .clipShape(Capsule())
    }
}

struct DeviceStatusIndicator: View {
    let status: WatchDeviceStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}

#Preview("Status Badges") {
    ScrollView {
        VStack(spacing: 8) {
            ForEach(WatchSessionStatus.allCases, id: \.self) { status in
                StatusBadge(status: status)
            }

            Divider()

            ForEach(WatchSessionStatus.allCases, id: \.self) { status in
                StatusBadge(status: status, compact: true)
            }
        }
    }
}
