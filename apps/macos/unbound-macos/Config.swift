//
//  Config.swift
//  unbound-macos
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
    private static let defaultLocalAPIURL = URL(string: "http://localhost:3000")!
    private static let defaultProdAPIURL = URL(string: "https://unbound.computer")!
    private static let defaultPresenceDOTTLMS = 12_000

    // MARK: - API

    /// The main API URL
    static var apiURL: URL {
        if let raw = readOptionalConfigValue(env: "API_URL", plist: "API_URL"),
           let url = URL(string: raw)
        {
            return url
        }
        #if DEBUG
        return defaultLocalAPIURL
        #else
        return defaultProdAPIURL
        #endif
    }

    // MARK: - Supabase

    /// Supabase project URL
    static var supabaseURL: URL {
        if let raw = readOptionalConfigValue(env: "SUPABASE_URL", plist: "SUPABASE_URL"),
           let url = URL(string: raw)
        {
            return url
        }
        #if DEBUG
        // Local Supabase
        return URL(string: "http://127.0.0.1:54321")!
        #else
        // Production Supabase - replace with your actual URL
        return URL(string: "https://your-project.supabase.co")!
        #endif
    }

    /// Supabase publishable key
    static var supabasePublishableKey: String {
        if let key = readOptionalConfigValue(
            env: "SUPABASE_PUBLISHABLE_KEY",
            plist: "SUPABASE_PUBLISHABLE_KEY"
        ) {
            return key
        }
        #if DEBUG
        // Local Supabase default publishable key
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        #else
        // Production key - should be set properly
        return ""
        #endif
    }

    // MARK: - Daemon Paths

    /// Base directory name (e.g. ".unbound-dev" or ".unbound")
    static var baseDirName: String {
        if let value = readOptionalConfigValue(env: "UNBOUND_BASE_DIR", plist: "UNBOUND_BASE_DIR") {
            return value
        }
        #if DEBUG
        return ".unbound-dev"
        #else
        return ".unbound"
        #endif
    }

    /// Full path to the daemon base directory
    static var daemonBaseDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/\(baseDirName)"
    }

    /// Full path to the daemon socket
    static var socketPath: String {
        "\(daemonBaseDir)/daemon.sock"
    }

    // MARK: - OAuth Configuration

    /// OAuth redirect URL scheme for deep linking
    static var oauthRedirectScheme: String {
        if let value = readOptionalConfigValue(env: "UNBOUND_URL_SCHEME", plist: "UNBOUND_URL_SCHEME") {
            return value
        }
        #if DEBUG
        return "unbound-dev"
        #else
        return "unbound"
        #endif
    }

    /// Full OAuth redirect URL for Supabase auth callbacks
    static var oauthRedirectURL: URL {
        URL(string: "\(oauthRedirectScheme)://auth/callback")!
    }

    /// Bundle identifier for the app
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.unbound.macos"
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

    // MARK: - Presence DO

    static var presenceDOHeartbeatURL: String? {
        readOptionalConfigValue(
            env: "UNBOUND_PRESENCE_DO_HEARTBEAT_URL",
            plist: "UNBOUND_PRESENCE_DO_HEARTBEAT_URL"
        )
    }

    static var presenceDOToken: String? {
        readOptionalConfigValue(
            env: "UNBOUND_PRESENCE_DO_TOKEN",
            plist: "UNBOUND_PRESENCE_DO_TOKEN"
        )
    }

    static var presenceDOTTLMS: Int {
        if let raw = readOptionalConfigValue(
            env: "UNBOUND_PRESENCE_DO_TTL_MS",
            plist: "UNBOUND_PRESENCE_DO_TTL_MS"
        ),
           let value = Int(raw),
           value > 0
        {
            return value
        }
        return defaultPresenceDOTTLMS
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

    /// Log current configuration (debug only)
    static func printConfig() {
        #if DEBUG
        logger.debug("Config:")
        logger.debug("  - API URL: \(apiURL)")
        logger.debug("  - Supabase URL: \(supabaseURL)")
        logger.debug("  - OAuth Redirect: \(oauthRedirectURL)")
        logger.debug("  - Daemon Base Dir: \(daemonBaseDir)")
        logger.debug("  - Socket Path: \(socketPath)")
        logger.debug("  - Debug Mode: \(isDebug)")
        logger.debug("  - Observability Mode: \(observabilityMode)")
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
