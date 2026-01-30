//
//  unbound_iosApp.swift
//  unbound-ios
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import SwiftUI
import UIKit
import Logging

private let logger = Logger(label: "app.main")

/// App initialization state
enum AppInitState {
    case loading(message: String, progress: Double)
    case ready
    case failed(Error)
}

@main
struct unbound_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    // View-owned state (correct usage of @State)
    @State private var initState: AppInitState = .loading(message: "Starting...", progress: 0.0)
    @State private var navigationManager = NavigationManager()
    @State private var showTrustOnboarding = false

    init() {
        LoggingService.bootstrap()
    }

    // Singleton services - accessed directly, not wrapped in @State
    private var authService: AuthService { AuthService.shared }
    private var deviceTrustService: DeviceTrustService { DeviceTrustService.shared }
    private var relayService: RelayConnectionService { RelayConnectionService.shared }
    private var pushService: PushNotificationService { PushNotificationService.shared }
    private var deepLinkRouter: DeepLinkRouter { DeepLinkRouter.shared }
    private var trustStatusService: DeviceTrustStatusService { DeviceTrustStatusService.shared }
    private var presenceService: DevicePresenceService { DevicePresenceService.shared }

    var body: some Scene {
        WindowGroup {
            Group {
                switch initState {
                case .loading(let message, let progress):
                    SplashView(statusMessage: message, progress: progress)

                case .failed(let error):
                    InitializationErrorView(error: error, onRetry: {
                        Task {
                            await initialize()
                        }
                    })

                case .ready:
                    mainContent
                }
            }
            .environment(AuthService.shared)
            .environment(\.navigationManager, navigationManager)
            .environment(\.deviceTrustService, DeviceTrustService.shared)
            .environment(\.relayService, RelayConnectionService.shared)
            .environment(\.pushNotificationService, PushNotificationService.shared)
            .environment(\.deepLinkRouter, DeepLinkRouter.shared)
            .tint(AppTheme.accent)
            .onOpenURL { url in
                handleDeepLink(url: url)
            }
            .task {
                await initialize()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Send immediate heartbeat when app becomes active
                    Task {
                        await presenceService.sendImmediateHeartbeat()
                    }
                }
            }
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        initState = .loading(message: "Starting...", progress: 0.0)

        do {
            // Step 1: Initialize database (device identity is initialized after auth)
            _ = try await AppInitializer.shared.initializeAsync { message, progress in
                initState = .loading(message: message, progress: progress * 0.5)
            }

            // Step 2: Load auth session
            initState = .loading(message: "Checking session...", progress: 0.6)
            await authService.loadSession()
            authService.startListening()

            // Step 3: If authenticated, register device (includes device identity initialization)
            if authService.authState.isAuthenticated {
                initState = .loading(message: "Registering device...", progress: 0.8)
                await authService.registerDevice()
            }

            initState = .ready
        } catch {
            initState = .failed(error)
        }
    }

    // MARK: - Main Content (after initialization)

    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch authService.authState {
            case .unknown:
                LoadingView()
            case .unauthenticated, .error:
                AuthView()
            case .authenticating:
                LoadingView()
            case .authenticated:
                authenticatedContent
            }
        }
        .onChange(of: authService.authState) { _, newValue in
            handleAuthStateChange(newValue)
        }
    }

    // MARK: - Authenticated Content

    @ViewBuilder
    private var authenticatedContent: some View {
        // Wrap with PostLoginSyncWrapper to sync device to Supabase
        PostLoginSyncWrapper {
            ZStack {
                NavigationStack(path: $navigationManager.path) {
                    DeviceListView()
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .deviceDetail(let device):
                                DeviceDetailView(device: device)
                            case .syncedDeviceDetail(let device):
                                SyncedDeviceDetailView(device: device)
                            case .projectDetail(let device, let project):
                                ProjectDetailView(device: device, project: project)
                            case .chat(let chat):
                                ChatView(chat: chat)
                            case .newChat(let project):
                                ChatView(chat: nil, project: project)
                            case .accountSettings:
                                AccountSettingsView()
                            }
                        }
                }

                // Full-screen trust onboarding overlay - blocks all interaction until trusted
                if showTrustOnboarding {
                    TrustOnboardingView { trusted in
                        showTrustOnboarding = false
                    }
                }
            }
        }
        .task {
            // Connect to relay on authenticated content appear
            await connectToRelay()
            // Request push notification authorization
            await pushService.requestAuthorization()
            // Check if we should show trust onboarding
            await checkTrustOnboarding()
        }
    }

    // MARK: - Trust Onboarding

    private func checkTrustOnboarding() async {
        // Wait a brief moment for device registration to complete
        try? await Task.sleep(for: .seconds(1))

        // Fetch current trust status from Supabase
        try? await trustStatusService.fetchTrustStatus()

        // Show onboarding if user hasn't seen it yet
        await MainActor.run {
            if trustStatusService.shouldShowTrustOnboarding {
                showTrustOnboarding = true
            }
        }
    }

    // MARK: - Relay Connection

    private func connectToRelay() async {
        do {
            let token = try await authService.getAccessToken()
            relayService.connect(to: Config.relayWebSocketURL, authToken: token)
        } catch {
            logger.error("Failed to get access token for relay: \(error)")
        }
    }

    // MARK: - Auth State Changes

    private func handleAuthStateChange(_ newState: AuthState) {
        switch newState {
        case .authenticated:
            // Relay connection is handled by .task on authenticatedContent
            break

        case .unauthenticated, .error:
            // Disconnect from relay when logged out
            relayService.disconnect()
            // Clear cached push token
            pushService.clearCachedToken()

        default:
            break
        }
    }

    // MARK: - Deep Linking

    private func handleDeepLink(url: URL) {
        Task {
            _ = await deepLinkRouter.handleDeepLink(
                url,
                authService: authService,
                navigationManager: navigationManager
            )
        }
    }
}
