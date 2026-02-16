//
//  ContentView.swift
//  unbound-macos
//
//  Main content view with shadcn styling.
//  Gates app behind daemon connection and authentication.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Group {
            switch appState.daemonConnectionState {
            case .disconnected, .connecting:
                // Connecting to daemon
                DaemonConnectingView()
                    .transition(.opacity)

            case .failed(let reason):
                // Daemon connection failed
                DaemonErrorView(reason: reason) {
                    Task {
                        await appState.retryDaemonConnection()
                    }
                }
                .transition(.opacity)

            case .connected:
                // Daemon connected - check auth
                connectedContent
            }
        }
        .background(colors.background)
        .animation(.easeInOut(duration: Duration.medium), value: appState.daemonConnectionState)
        .task {
            // Connect to daemon on first appearance
            if !appState.isDaemonConnected {
                await appState.connectToDaemon()
            }
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
        if appState.isAuthenticated {
            if appState.dependenciesSatisfied {
                // Show main app
                ZStack {
                    WorkspaceView()
                        .opacity(appState.showSettings ? 0 : 1)

                    if appState.showSettings {
                        SettingsView()
                    }
                }
                .animation(.easeInOut(duration: Duration.default), value: appState.showSettings)
            } else {
                // Dependency check gate
                DependencyCheckView()
                    .transition(.opacity)
            }
        } else if appState.isAuthValidationPending {
            AuthRestoringView()
                .transition(.opacity)
        } else {
            // Show login
            OnboardingView()
                .transition(.opacity)
        }
    }
}

// MARK: - Auth Restoring View

struct AuthRestoringView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            VStack(spacing: Spacing.sm) {
                Text("Restoring Session")
                    .font(Typography.title2)
                    .foregroundColor(colors.foreground)

                Text("Validating saved credentials...")
                    .font(Typography.body)
                    .foregroundColor(colors.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Daemon Connecting View

struct DaemonConnectingView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            VStack(spacing: Spacing.sm) {
                Text("Connecting to Unbound")
                    .font(Typography.title2)
                    .foregroundColor(colors.foreground)

                Text("Starting daemon service...")
                    .font(Typography.body)
                    .foregroundColor(colors.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Daemon Error View

struct DaemonErrorView: View {
    let reason: String
    let onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(colors.destructive)

            VStack(spacing: Spacing.sm) {
                Text("Daemon Not Running")
                    .font(Typography.title2)
                    .foregroundColor(colors.foreground)

                Text(reason)
                    .font(Typography.body)
                    .foregroundColor(colors.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(spacing: Spacing.md) {
                Button(action: onRetry) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Connection")
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.borderedProminent)

                Text("Make sure the Unbound daemon is installed.")
                    .font(Typography.caption)
                    .foregroundColor(colors.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Connected - Authenticated") {
    ContentView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}

#Preview("Daemon Error") {
    DaemonErrorView(reason: "Daemon socket not found. Is the daemon running?") {}
        .frame(width: 600, height: 400)
}
