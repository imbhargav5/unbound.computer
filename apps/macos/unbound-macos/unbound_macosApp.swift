//
//  unbound_macosApp.swift
//  unbound-macos
//
//  Main app entry with shadcn design system.
//  Thin client that connects to daemon for all business logic.
//

import SwiftUI
import Logging

private let logger = Logger(label: "app.main")

/// Initialization state for the app
enum InitializationState {
    case loading(message: String, progress: Double)
    case ready
    case failed(Error)
}

@main
struct unbound_macosApp: App {
    @State private var initializationState: InitializationState = .loading(message: "Starting...", progress: 0)
    @State private var appState: AppState?

    init() {
        LoggingService.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch initializationState {
                case .loading(let message, let progress):
                    SplashView(statusMessage: message, progress: progress)
                        .frame(minWidth: 900, minHeight: 600)

                case .ready:
                    if let appState {
                        ContentView()
                            .environment(appState)
                            .environment(\.themeColors, ThemeColors(appState.themeMode.colorScheme ?? .dark))
                            .preferredColorScheme(appState.themeMode.colorScheme)
                            .frame(minWidth: 900, minHeight: 600)
                    }

                case .failed(let error):
                    InitializationErrorView(error: error) {
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
                if url.scheme == "unbound" && url.host == "auth" {
                    Task {
                        await appState?.refreshAuthStatus()
                        if appState?.isAuthenticated == true {
                            await appState?.loadDataAsync()
                        }
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

        // Settings window - only show when app is ready
        Settings {
            if let appState {
                SettingsView()
                    .environment(appState)
                    .environment(\.themeColors, ThemeColors(appState.themeMode.colorScheme ?? .dark))
                    .preferredColorScheme(appState.themeMode.colorScheme)
            }
        }
    }

    /// Initialize the app asynchronously
    private func initialize() async {
        logger.info("App initialize() called")

        // Reset to loading state
        initializationState = .loading(message: "Starting...", progress: 0)

        do {
            // Update progress: Creating state
            await MainActor.run {
                initializationState = .loading(message: "Initializing...", progress: 0.2)
            }

            // Create AppState
            logger.info("Creating AppState...")
            let state = AppState()
            logger.info("AppState created")

            // Update progress: Connecting to daemon
            await MainActor.run {
                initializationState = .loading(message: "Connecting to daemon...", progress: 0.4)
            }

            // Connect to daemon (this handles auth check and data loading)
            logger.info("Connecting to daemon...")
            await state.connectToDaemon()
            logger.info("Daemon connection complete")

            // Check if connection succeeded
            if case .failed(let reason) = state.daemonConnectionState {
                throw DaemonError.connectionFailed(reason)
            }

            // Update progress: Ready
            await MainActor.run {
                initializationState = .loading(message: "Ready", progress: 1.0)
            }

            logger.info("Updating UI state to ready...")
            await MainActor.run {
                self.appState = state
                self.initializationState = .ready
            }
            logger.info("UI state updated to ready")

        } catch {
            logger.error("Initialization failed: \(error.localizedDescription)")
            await MainActor.run {
                self.initializationState = .failed(error)
            }
        }
    }
}
