//
//  unbound_macosApp.swift
//  unbound-macos
//
//  Main app entry with shadcn design system.
//  Thin client that connects to daemon for all business logic.
//  Uses non-blocking initialization to show UI immediately.
//

import SwiftUI
import Logging

private let logger = Logger(label: "app.main")

private enum AppRuntime {
    static var isPreview: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
            environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}

/// Initialization state for the app
enum InitializationState: Equatable {
    case loading(message: String, progress: Double)
    case ready
    case readyOffline  // UI ready but daemon not connected
    case failed(String)

    static func == (lhs: InitializationState, rhs: InitializationState) -> Bool {
        switch (lhs, rhs) {
        case (.loading(let m1, let p1), .loading(let m2, let p2)):
            return m1 == m2 && p1 == p2
        case (.ready, .ready):
            return true
        case (.readyOffline, .readyOffline):
            return true
        case (.failed(let e1), .failed(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

@main
struct unbound_macosApp: App {
    @State private var initializationState: InitializationState = .loading(message: "Starting...", progress: 0)
    @State private var appState: AppState?

    init() {
        if !AppRuntime.isPreview {
            // Register Geist fonts and logging only for real app runtime.
            // Previews don't need global bootstrap and should stay minimal.
            FontRegistration.registerFonts()
            LoggingService.bootstrap()
        }
    }

    var body: some Scene {
        WindowGroup {
            if AppRuntime.isPreview {
                Color.clear
                    .frame(width: 1, height: 1)
            } else {
                Group {
                    switch initializationState {
                    case .loading(let message, let progress):
                        SplashView(statusMessage: message, progress: progress)
                            .frame(minWidth: 900, minHeight: 600)

                    case .ready, .readyOffline:
                        if let appState {
                            ContentView()
                                .environment(appState)
                                .environment(\.themeColors, ThemeColors(appState.themeMode.colorScheme ?? .dark))
                                .preferredColorScheme(appState.themeMode.colorScheme)
                                .frame(minWidth: 900, minHeight: 600)
                                .overlay(alignment: .top) {
                                    // Show connection status banner when offline
                                    if initializationState == .readyOffline || !appState.isDaemonConnected {
                                        DaemonConnectionBanner(
                                            state: appState.daemonConnectionState,
                                            onRetry: {
                                                Task {
                                                    await appState.retryDaemonConnection()
                                                    if appState.isDaemonConnected {
                                                        initializationState = .ready
                                                    }
                                                }
                                            }
                                        )
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }
                                .animation(.easeInOut(duration: 0.3), value: appState.isDaemonConnected)
                        }

                    case .failed(let errorMessage):
                        InitializationErrorView(error: DaemonError.connectionFailed(errorMessage)) {
                            // Retry initialization
                            Task {
                                await initialize()
                            }
                        }
                        .frame(minWidth: 900, minHeight: 600)
                    }
                }
                .task {
                    await initialize()
                }
                .onOpenURL { url in
                    // Handle deep links (OAuth callbacks)
                    // Daemon handles auth, so just log for now
                    logger.info("Deep link received: \(url.absoluteString)")

                    // If this is an auth callback, refresh auth status
                    if url.scheme == Config.oauthRedirectScheme && url.host == "auth" {
                        Task {
                            await appState?.refreshAuthStatus()
                            if appState?.isAuthenticated == true {
                                await appState?.loadDataAsync()
                            }
                        }
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

        // Settings window - only show when app is ready
        Settings {
            if !AppRuntime.isPreview, let appState {
                SettingsView()
                    .environment(appState)
                    .environment(\.themeColors, ThemeColors(appState.themeMode.colorScheme ?? .dark))
                    .preferredColorScheme(appState.themeMode.colorScheme)
            }
        }
    }

    /// Initialize the app asynchronously with non-blocking UI.
    /// Shows UI immediately and connects to daemon in background.
    private func initialize() async {
        logger.info("App initialize() called")

        // Reset to loading state
        initializationState = .loading(message: "Starting...", progress: 0)

        // Install CLI symlink so terminal users get the bundled daemon
        DaemonLauncher.installCLISymlink()

        // Create AppState immediately so UI can render
        logger.info("Creating AppState...")
        let state = AppState()
        logger.info("AppState created")

        // Show UI immediately with "connecting" state
        await MainActor.run {
            self.appState = state
            initializationState = .loading(message: "Connecting to daemon...", progress: 0.5)
        }

        // Connect to daemon in background - don't block UI
        await connectToDaemonNonBlocking(state: state)
    }

    /// Connect to daemon without blocking UI initialization.
    /// If connection fails, show UI in offline mode instead of error screen.
    private func connectToDaemonNonBlocking(state: AppState) async {
        logger.info("Connecting to daemon (non-blocking)...")

        // Use a timeout for the entire connection process
        let connectionSucceeded = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await state.connectToDaemon()
                return state.daemonConnectionState.isConnected
            }

            group.addTask {
                // Timeout after 15 seconds total
                try? await Task.sleep(for: .seconds(15))
                return false
            }

            // Return first result
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        await MainActor.run {
            if connectionSucceeded {
                logger.info("Daemon connected successfully")
                self.initializationState = .ready
            } else if case .failed(let reason) = state.daemonConnectionState {
                logger.warning("Daemon connection failed: \(reason), showing UI in offline mode")
                // Show UI anyway - user can retry connection
                self.initializationState = .readyOffline
            } else {
                logger.warning("Daemon connection timed out, showing UI in offline mode")
                self.initializationState = .readyOffline
            }
        }

        logger.info("UI state updated, connection status: \(connectionSucceeded ? "connected" : "offline")")
    }
}
