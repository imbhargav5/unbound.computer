//
//  DeepLinkRouter.swift
//  unbound-ios
//
//  Centralized deep link routing for authentication callbacks and navigation.
//

import Foundation
import Logging
import SwiftUI

private let logger = Logger(label: "app.network")

/// Deep link routes supported by the app
enum DeepLinkRoute: Equatable, Hashable {
    case authCallback(URL)
    case dashboard
    case settings
    case chat(id: String)
    case device(id: String)
    case unknown(String)
}

/// Service for parsing and routing deep links
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    // Observable property for SwiftUI navigation
    private(set) var pendingRoute: DeepLinkRoute?

    private init() {}

    /// Parse a deep link URL into a route
    func parse(_ url: URL) -> DeepLinkRoute {
        logger.debug("Parsing deep link: \(url.absoluteString)")

        guard url.scheme == Config.oauthRedirectScheme else {
            logger.warning("Unknown URL scheme: \(url.scheme ?? "nil")")
            return .unknown(url.absoluteString)
        }

        let host = url.host ?? ""
        let path = url.path

        // Check for auth callback (has query parameters like code or access_token)
        if host == "auth" && path == "/callback" {
            logger.debug("Detected auth callback")
            return .authCallback(url)
        }

        // Navigation routes
        switch host {
        case "dashboard":
            logger.debug("Routing to dashboard")
            return .dashboard

        case "settings":
            logger.debug("Routing to settings")
            return .settings

        case "chat":
            // Format: unbound-ios://chat/<id>
            let chatId = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !chatId.isEmpty {
                logger.debug("Routing to chat: \(chatId)")
                return .chat(id: chatId)
            }
            return .unknown(url.absoluteString)

        case "device":
            // Format: unbound-ios://device/<id>
            let deviceId = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !deviceId.isEmpty {
                logger.debug("Routing to device: \(deviceId)")
                return .device(id: deviceId)
            }
            return .unknown(url.absoluteString)

        default:
            logger.warning("Unknown deep link route: \(host)\(path)")
            return .unknown(url.absoluteString)
        }
    }

    /// Handle a deep link by parsing and routing it
    func handleDeepLink(_ url: URL, authService: AuthService?, navigationManager: NavigationManager?) async -> Bool {
        let route = parse(url)

        switch route {
        case .authCallback(let authUrl):
            // Delegate auth callbacks to AuthService
            guard let authService else {
                logger.warning("Cannot handle auth callback - authService not ready")
                return false
            }

            // Check if this is an OAuth callback
            guard authUrl.scheme == Config.oauthRedirectScheme,
                  authUrl.host == "auth",
                  authUrl.path == "/callback" else {
                return false
            }

            do {
                try await authService.handleOAuthCallback(url: authUrl)
                return true
            } catch {
                logger.warning("OAuth callback failed: \(error)")
                return false
            }

        case .dashboard, .settings, .chat, .device:
            // Store route for navigation
            await MainActor.run {
                self.pendingRoute = route
            }
            return true

        case .unknown(let urlString):
            logger.warning("Could not route deep link: \(urlString)")
            return false
        }
    }

    /// Clear the pending route after it's been handled
    func clearPendingRoute() {
        pendingRoute = nil
    }
}

// MARK: - SwiftUI Environment

private struct DeepLinkRouterKey: EnvironmentKey {
    static let defaultValue = DeepLinkRouter.shared
}

extension EnvironmentValues {
    var deepLinkRouter: DeepLinkRouter {
        get { self[DeepLinkRouterKey.self] }
        set { self[DeepLinkRouterKey.self] = newValue }
    }
}
