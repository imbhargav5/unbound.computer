//
//  Config.swift
//  unbound-ios
//
//  Environment configuration for the app.
//  Uses compile-time flags to switch between development and production.
//

import Foundation
import Logging

private let logger = Logger(label: "app.config")

enum ObservabilityMode {
    case devVerbose
    case prodMetadataOnly
}

enum Config {
    // MARK: - API

    /// The main API URL
    static var apiURL: URL {
        #if DEBUG
        if let envURL = ProcessInfo.processInfo.environment["API_URL"],
           let url = URL(string: envURL) {
            return url
        }
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://unbound.computer")!
        #endif
    }

    // MARK: - Supabase

    /// Supabase project URL
    static var supabaseURL: URL {
        guard let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !envURL.isEmpty,
              let url = URL(string: envURL) else {
            fatalError("SUPABASE_URL must be set to a valid URL")
        }
        return url
    }

    /// Supabase publishable key
    static var supabasePublishableKey: String {
        guard let key = ProcessInfo.processInfo.environment["SUPABASE_PUBLISHABLE_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            fatalError("SUPABASE_PUBLISHABLE_KEY must be set")
        }
        return key
    }

    // MARK: - Ably

    /// Mobile token-auth endpoint used by the Ably realtime transport.
    static var ablyTokenAuthURL: URL {
        apiURL.appendingPathComponent("api/v1/mobile/ably/token")
    }

    static let remoteCommandEventName = "remote.command.v1"
    static let remoteCommandAckEventName = "remote.command.ack.v1"
    static let sessionSecretResponseEventName = "session.secret.response.v1"
    static let remoteCommandResponseEventName = "remote.command.response.v1"
    static let daemonPresenceEventName = "daemon.presence.v1"

    static func daemonPresenceChannel(userId: String) -> String {
        "presence:\(userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    // MARK: - Ably Conversation

    static let conversationMessageEventName = "conversation.message.v1"

    /// Returns the Ably channel name for a session's conversation messages.
    static func conversationChannel(sessionId: UUID) -> String {
        "session:\(sessionId.uuidString.lowercased()):conversation"
    }

    // MARK: - Ably Runtime Status (LiveObjects)

    static let runtimeStatusObjectKey = "coding_session_status"

    /// Returns the Ably channel name for a session's runtime-status object updates.
    static func runtimeStatusChannel(sessionId: UUID) -> String {
        "session:\(sessionId.uuidString.lowercased()):status"
    }

    /// Force recreation of local SQLite database on app launch (debug only).
    /// Set `RECREATE_LOCAL_DB_ON_LAUNCH=1` in scheme environment variables.
    static var recreateLocalDatabaseOnLaunch: Bool {
        #if DEBUG
        guard let rawValue = ProcessInfo.processInfo.environment["RECREATE_LOCAL_DB_ON_LAUNCH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes"
        #else
        return false
        #endif
    }

    /// OAuth redirect URL scheme
    static let oauthRedirectScheme = "unbound-ios"

    /// OAuth redirect URL for authentication callbacks
    static var oauthRedirectURL: URL {
        URL(string: "\(oauthRedirectScheme)://auth/callback")!
    }

    // MARK: - Debug Helpers

    /// Whether we're running in debug mode
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Observability

    static var observabilityMode: ObservabilityMode {
        if let raw = ProcessInfo.processInfo.environment["UNBOUND_OBS_MODE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
            if raw == "prod" || raw == "production" {
                return .prodMetadataOnly
            }
            if raw == "dev" || raw == "development" {
                return .devVerbose
            }
        }
        return isDebug ? .devVerbose : .prodMetadataOnly
    }

    static var posthogAPIKey: String? {
        readOptionalConfigValue(env: "POSTHOG_API_KEY", plist: "POSTHOG_API_KEY")
    }

    static var posthogHost: URL {
        if let raw = readOptionalConfigValue(env: "POSTHOG_HOST", plist: "POSTHOG_HOST"),
           let url = URL(string: raw)
        {
            return url
        }
        return URL(string: "https://us.i.posthog.com")!
    }

    static var sentryDSN: String? {
        readOptionalConfigValue(env: "SENTRY_DSN", plist: "SENTRY_DSN")
    }

    static var observabilityInfoSampleRate: Double {
        if let raw = readOptionalConfigValue(env: "UNBOUND_OBS_INFO_SAMPLE_RATE", plist: "UNBOUND_OBS_INFO_SAMPLE_RATE"),
           let value = Double(raw)
        {
            return min(max(value, 0.0), 1.0)
        }
        return isDebug ? 1.0 : 0.1
    }

    static var observabilityDebugSampleRate: Double {
        if let raw = readOptionalConfigValue(env: "UNBOUND_OBS_DEBUG_SAMPLE_RATE", plist: "UNBOUND_OBS_DEBUG_SAMPLE_RATE"),
           let value = Double(raw)
        {
            return min(max(value, 0.0), 1.0)
        }
        return isDebug ? 1.0 : 0.0
    }

    static var observabilityEnvironment: String {
        switch observabilityMode {
        case .devVerbose:
            return "development"
        case .prodMetadataOnly:
            return "production"
        }
    }

    /// Print current configuration (debug only)
    static func printConfig() {
        #if DEBUG
        logger.debug("Config: API URL: \(apiURL), Supabase URL: \(supabaseURL), Debug Mode: \(isDebug), Recreate DB On Launch: \(recreateLocalDatabaseOnLaunch), Observability Mode: \(observabilityMode)")
        #endif
    }

    private static func readOptionalConfigValue(env: String, plist: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[env]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty
        {
            return value
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: plist) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}
