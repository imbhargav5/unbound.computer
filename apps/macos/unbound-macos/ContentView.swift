//
//  ContentView.swift
//  unbound-macos
//
//  Main content view with shadcn styling.
//  Gates app behind daemon connection and local dependency checks.
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
        if appState.dependenciesSatisfied {
            if !appState.hasCompletedInitialCompanyLoad {
                DaemonConnectingView(
                    title: "Loading spaces",
                    message: "Checking local spaces before opening Unbound..."
                )
                .transition(.opacity)
            } else if let boardError = appState.boardError,
                      appState.hasCompletedInitialCompanyLoad,
                      appState.companies.isEmpty {
                InitialCompanyLoadErrorView(message: boardError) {
                    Task {
                        await appState.loadBoardDataAsync()
                    }
                }
                .transition(.opacity)
            } else if appState.currentShell == .firstCompanySetup {
                CreateFirstCompanyView()
                    .transition(.opacity)
            } else if appState.currentShell == .ceoSetupRequired {
                CreateCEOAgentView()
                    .transition(.opacity)
            } else {
                BoardRootView()
            }
        } else {
            DependencyCheckView()
                .transition(.opacity)
        }
    }
}

// MARK: - Daemon Connecting View

struct DaemonConnectingView: View {
    @Environment(\.colorScheme) private var colorScheme

    var title: String = "Connecting to Unbound"
    var message: String = "Starting daemon service..."

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.title2)
                    .foregroundColor(colors.foreground)

                Text(message)
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

#if DEBUG

#Preview("Connected") {
    ContentView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}

#Preview("Daemon Error") {
    DaemonErrorView(reason: "Daemon socket not found. Is the daemon running?") {}
        .frame(width: 600, height: 400)
}

#endif
