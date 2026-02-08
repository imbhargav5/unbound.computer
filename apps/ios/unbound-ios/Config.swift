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
        #if DEBUG
        if let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let url = URL(string: envURL) {
            return url
        }
        // Local Supabase (localhost works for iOS Simulator)
        return URL(string: "http://localhost:54321")!
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
        logger.debug("Config: API URL: \(apiURL), Supabase URL: \(supabaseURL), Debug Mode: \(isDebug)")
        #endif
    }
}
