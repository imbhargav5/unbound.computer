//
//  SyncedDeviceRowView.swift
//  unbound-ios
//
//  Row view for displaying a synced device from Supabase.
//

import SwiftUI

struct SyncedDeviceRowView: View {
    let device: SyncedDevice

    @State private var isPressed = false

    private let syncedDataService = SyncedDataService.shared

    /// Count of repositories/sessions associated with this device
    private var projectCount: Int {
        // For now, show total repositories synced (sessions are per-device on macOS)
        syncedDataService.repositories.count
    }

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Device Icon
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: device.deviceType.iconName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            // Device Info
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text(device.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if let hostname = device.hostname {
                    Text(hostname)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: AppTheme.spacingS) {
                    SyncedDeviceStatusIndicator(status: device.status)

                    Text("\(projectCount) project\(projectCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
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
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }

    func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }
}

// MARK: - Status Indicator for SyncedDevice

struct SyncedDeviceStatusIndicator: View {
    let status: SyncedDevice.DeviceStatus

    private var statusColor: Color {
        switch status {
        case .online:
            return .green
        case .offline:
            return .gray
        case .busy:
            return .orange
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.displayName)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SyncedDeviceRowView(device: SyncedDevice(
            id: UUID(),
            name: "Bhargav's MacBook Pro",
            deviceType: .macDesktop,
            hostname: "bhargavs-mbp.local",
            isActive: true,
            lastSeenAt: Date(),
            createdAt: Date()
        ))
        SyncedDeviceRowView(device: SyncedDevice(
            id: UUID(),
            name: "Office Mac Mini",
            deviceType: .macDesktop,
            hostname: "office-mac.local",
            isActive: true,
            lastSeenAt: Date().addingTimeInterval(-300),
            createdAt: Date()
        ))
    }
    .padding()
    .background(Color(.systemBackground))
}
