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
        #if DEBUG
        if let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let url = URL(string: envURL) {
            return url
        }
        // Local Supabase
        return URL(string: "http://127.0.0.1:54321")!
        #else
        // Production Supabase - replace with your actual URL
        return URL(string: "https://your-project.supabase.co")!
        #endif
    }

    /// Supabase publishable key
    static var supabasePublishableKey: String {
        #if DEBUG
        if let key = ProcessInfo.processInfo.environment["SUPABASE_PUBLISHABLE_KEY"] {
            return key
        }
        // Local Supabase default publishable key
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        #else
        // Production key - should be set properly
        return ProcessInfo.processInfo.environment["SUPABASE_PUBLISHABLE_KEY"] ?? ""
        #endif
    }

    // MARK: - OAuth Configuration

    /// OAuth redirect URL scheme for deep linking
    static let oauthRedirectScheme = "unbound"

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

    /// Log current configuration (debug only)
    static func printConfig() {
        #if DEBUG
        logger.debug("Config:")
        logger.debug("  - API URL: \(apiURL)")
        logger.debug("  - Supabase URL: \(supabaseURL)")
        logger.debug("  - OAuth Redirect: \(oauthRedirectURL)")
        logger.debug("  - Debug Mode: \(isDebug)")
        #endif
    }
}
