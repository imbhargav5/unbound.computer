//
//  NetworkSettings.swift
//  unbound-macos
//
//  Network settings - placeholder for daemon mode.
//  Device pairing and network features are handled by daemon.
//

import SwiftUI

struct NetworkSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        SettingsPageContainer(title: "Network", subtitle: "Network and device pairing features are managed by the Unbound daemon.") {
            daemonConnectionSection

            VStack(spacing: Spacing.lg) {
                Image(systemName: "network")
                    .font(.system(size: 48))
                    .foregroundStyle(colors.mutedForeground)

                Text("Daemon Managed")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)

                Text("Device pairing and relay connections are handled by the daemon service.")
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(colors.muted.opacity(0.3))
            )
        }
    }

    // MARK: - Daemon Connection Section

    private var daemonConnectionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Daemon Connection")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            HStack(spacing: Spacing.lg) {
                // Connection indicator
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(appState.isDaemonConnected ? colors.success : colors.destructive)
                        .frame(width: 8, height: 8)

                    Text("Unbound Daemon")
                        .font(Typography.body)
                        .foregroundStyle(colors.foreground)
                }

                Spacer()

                Text(appState.daemonConnectionState.statusText)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                if !appState.isDaemonConnected {
                    Button("Reconnect") {
                        Task {
                            await appState.retryDaemonConnection()
                        }
                    }
                    .buttonOutline(size: .sm)
                }
            }
            .padding(Spacing.lg)
            .background(colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
    }
}

#if DEBUG

#Preview {
    NetworkSettings()
        .environment(AppState())
        .frame(width: 500, height: 600)
}

#endif
