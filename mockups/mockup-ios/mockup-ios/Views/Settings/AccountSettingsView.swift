import SwiftUI

struct AccountSettingsView: View {
    @State private var connectedDevices: [ConnectedDevice] = MockData.connectedDevices
    @State private var isConnecting = false
    @State private var connectionProgress: Double = 0
    @State private var showLogoutAlert = false
    @State private var isTrusted = true
    @State private var isUpdatingTrust = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingL) {
                // Account header
                accountHeader

                // Connected devices section
                connectedDevicesSection

                // Settings sections
                settingsSections
            }
            .padding(AppTheme.spacingM)
        }
        .background(AppTheme.backgroundPrimary)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Account Header

    private var accountHeader: some View {
        VStack(spacing: AppTheme.spacingM) {
            // Avatar
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient)
                    .frame(width: 80, height: 80)

                Text("BP")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color(UIColor.systemBackground))
            }

            VStack(spacing: AppTheme.spacingXS) {
                Text("bhargav@example.com")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Pro Plan")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, AppTheme.spacingS)
                    .padding(.vertical, AppTheme.spacingXS)
                    .background(AppTheme.toolBadgeBg)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacingL)
    }

    // MARK: - Connected Devices Section

    private var connectedDevicesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            HStack {
                Text("Connected Sessions")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text("\(connectedDevices.count) active")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if connectedDevices.isEmpty {
                EmptyStateView(
                    icon: "laptopcomputer.and.iphone",
                    title: "No Connected Devices",
                    message: "Scan a QR code from another device running Claude Code to connect."
                )
                .padding(.vertical, AppTheme.spacingL)
            } else {
                VStack(spacing: AppTheme.spacingS) {
                    ForEach(connectedDevices) { device in
                        ConnectedDeviceRow(device: device) {
                            disconnectDevice(device)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Settings Sections

    private var settingsSections: some View {
        VStack(spacing: AppTheme.spacingM) {
            // Device Security section
            SettingsSection(title: "Device Security") {
                HStack(spacing: AppTheme.spacingM) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.body)
                        .foregroundStyle(isTrusted ? AppTheme.accent : AppTheme.textSecondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trusted Device")
                            .font(.body)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(isTrusted ? "This device is trusted" : "Mark as trusted to enable full access")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    if isUpdatingTrust {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Toggle("", isOn: $isTrusted)
                            .labelsHidden()
                    }
                }
                .padding(AppTheme.spacingM)
                .background(AppTheme.cardBackground)
                .cornerRadius(AppTheme.cornerRadiusMedium)
            }

            // Preferences section
            SettingsSection(title: "Preferences") {
                SettingsRow(icon: "bell.badge", title: "Notifications", subtitle: "Manage alerts")
                SettingsRow(icon: "paintbrush", title: "Appearance", subtitle: "Theme & display")
                SettingsRow(icon: "lock.shield", title: "Privacy", subtitle: "Security settings")
            }

            // Support section
            SettingsSection(title: "Support") {
                SettingsRow(icon: "questionmark.circle", title: "Help Center", subtitle: nil)
                SettingsRow(icon: "envelope", title: "Contact Support", subtitle: nil)
                SettingsRow(icon: "doc.text", title: "Terms of Service", subtitle: nil)
            }

            // Logout section
            logoutSection

            // Version info
            HStack {
                Text("Version 1.0.0 (Build 1)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, AppTheme.spacingM)
        }
    }

    // MARK: - Logout Section

    private var logoutSection: some View {
        Button {
            showLogoutAlert = true
        } label: {
            HStack(spacing: AppTheme.spacingM) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(width: 24)

                Text("Sign Out")
                    .font(.body)
                    .foregroundStyle(.red)

                Spacer()
            }
            .padding(AppTheme.spacingM)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .alert("Sign Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                // Handle logout
            }
        } message: {
            Text("Are you sure you want to sign out? You'll need to sign in again to access your sessions.")
        }
    }

    // MARK: - Actions

    private func disconnectDevice(_ device: ConnectedDevice) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            connectedDevices.removeAll { $0.id == device.id }
        }
    }
}

// MARK: - Connected Device Model

struct ConnectedDevice: Identifiable {
    let id: UUID
    let name: String
    let hostname: String
    let connectedAt: Date
    var lastActive: Date
    let platform: Platform
    let sessionId: String

    enum Platform: String {
        case macOS = "macOS"
        case linux = "Linux"
        case windows = "Windows"

        var icon: String {
            switch self {
            case .macOS: return "laptopcomputer"
            case .linux: return "terminal"
            case .windows: return "pc"
            }
        }
    }
}

// MARK: - Connected Device Row

struct ConnectedDeviceRow: View {
    let device: ConnectedDevice
    let onDisconnect: () -> Void

    @State private var showDisconnectAlert = false

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Platform icon
            Image(systemName: device.platform.icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 40, height: 40)
                .background(AppTheme.toolBadgeBg)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))

            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(device.hostname)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Text("Connected \(device.connectedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            // Disconnect button
            Button {
                showDisconnectAlert = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(AppTheme.spacingS)
        .background(AppTheme.backgroundSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .alert("Disconnect Device?", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                onDisconnect()
            }
        } message: {
            Text("This will end the session on \(device.name). You can reconnect by scanning the QR code again.")
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.leading, AppTheme.spacingXS)

            VStack(spacing: 1) {
                content()
            }
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
    }
}

// MARK: - Mock Data Extension

extension MockData {
    static let connectedDevices: [ConnectedDevice] = [
        ConnectedDevice(
            id: UUID(),
            name: "MacBook Pro 16\"",
            hostname: "bhargav-mbp.local",
            connectedAt: Date().addingTimeInterval(-3600 * 2),
            lastActive: Date().addingTimeInterval(-60),
            platform: .macOS,
            sessionId: "session-abc123"
        )
    ]
}

// MARK: - Previews

#Preview {
    NavigationStack {
        AccountSettingsView()
    }
    .tint(AppTheme.accent)
}
