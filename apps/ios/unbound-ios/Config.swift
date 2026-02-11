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

    /// Debug-only Ably API key override for local testing.
    ///
    /// If set in DEBUG, iOS can use key auth temporarily instead of token auth.
    /// Production builds always return nil.
    static var ablyDevApiKey: String? {
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["ABLY_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return nil
        }
        return raw
        #else
        return nil
        #endif
    }

    /// Mobile token-auth endpoint used by the Ably realtime transport.
    static var ablyTokenAuthURL: URL {
        apiURL.appendingPathComponent("api/v1/mobile/ably/token")
    }

    static let remoteCommandEventName = "remote.command.v1"
    static let remoteCommandAckEventName = "remote.command.ack.v1"
    static let sessionSecretResponseEventName = "session.secret.response.v1"

    // MARK: - Ably Conversation

    static let conversationMessageEventName = "conversation.message.v1"

    /// Returns the Ably channel name for a session's conversation messages.
    static func conversationChannel(sessionId: UUID) -> String {
        "session:\(sessionId.uuidString.lowercased()):conversation"
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

    /// Print current configuration (debug only)
    static func printConfig() {
        #if DEBUG
        logger.debug("Config: API URL: \(apiURL), Supabase URL: \(supabaseURL), Debug Mode: \(isDebug), Recreate DB On Launch: \(recreateLocalDatabaseOnLaunch)")
        #endif
    }
}
