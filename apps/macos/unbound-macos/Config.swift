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

enum ObservabilityMode: Equatable {
    case devVerbose
    case prodMetadataOnly

    nonisolated var identifier: String {
        switch self {
        case .devVerbose:
            return "dev_verbose"
        case .prodMetadataOnly:
            return "prod_metadata_only"
        }
    }
}

enum ConfigValueSource: String, Equatable {
    case env
    case plist
    case unset
}

struct ResolvedConfigValue: Equatable {
    let value: String?
    let source: ConfigValueSource
}

struct ResolvedObservabilityStatus: Equatable {
    let otlpEnabled: Bool
    let endpointSource: ConfigValueSource
    let otlpBaseURL: URL?
    let otlpLogsURL: URL?
    let headersPresent: Bool
    let headerCount: Int
    let mode: ObservabilityMode
    let environment: String
    let infoSampleRate: Double
    let debugSampleRate: Double

    nonisolated var metadata: Logger.Metadata {
        var metadata: Logger.Metadata = [
            "otlp_enabled": .stringConvertible(otlpEnabled),
            "otlp_endpoint_source": .string(endpointSource.rawValue),
            "otlp_headers_present": .stringConvertible(headersPresent),
            "otlp_header_count": .stringConvertible(headerCount),
            "observability_mode": .string(mode.identifier),
            "observability_environment": .string(environment),
            "observability_info_sample_rate": .stringConvertible(infoSampleRate),
            "observability_debug_sample_rate": .stringConvertible(debugSampleRate)
        ]

        if let otlpBaseURL {
            metadata["otlp_base_url"] = .string(otlpBaseURL.absoluteString)
        }

        if let otlpLogsURL {
            metadata["otlp_logs_url"] = .string(otlpLogsURL.absoluteString)
        }

        return metadata
    }
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
        resolveObservabilityMode(
            environment: ProcessInfo.processInfo.environment,
            isDebug: isDebug
        )
    }

    static var otlpEndpoint: URL? {
        resolveOTLPEndpoint(
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        )
    }

    static var otlpHeaders: [String: String] {
        parseOTLPHeaders(
            raw: resolveConfigValue(
                env: "UNBOUND_OTEL_HEADERS",
                plist: "UNBOUND_OTEL_HEADERS",
                environment: ProcessInfo.processInfo.environment,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ).value
        )
    }

    static var resolvedObservabilityStatus: ResolvedObservabilityStatus {
        resolvedObservabilityStatus(
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            isDebug: isDebug
        )
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
        resolveSampleRate(
            env: "UNBOUND_OBS_INFO_SAMPLE_RATE",
            plist: "UNBOUND_OBS_INFO_SAMPLE_RATE",
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            defaultValue: isDebug ? 1.0 : 0.1
        )
    }

    static var observabilityDebugSampleRate: Double {
        resolveSampleRate(
            env: "UNBOUND_OBS_DEBUG_SAMPLE_RATE",
            plist: "UNBOUND_OBS_DEBUG_SAMPLE_RATE",
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            defaultValue: isDebug ? 1.0 : 0.0
        )
    }

    static var observabilityEnvironment: String {
        observabilityEnvironmentName(for: observabilityMode)
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
        logger.debug("  - OTLP Enabled: \(resolvedObservabilityStatus.otlpEnabled)")
        logger.debug("  - OTLP Endpoint Source: \(resolvedObservabilityStatus.endpointSource.rawValue)")
        logger.debug("  - OTLP Logs URL: \(resolvedObservabilityStatus.otlpLogsURL?.absoluteString ?? "unset")")
        #endif
    }

    private static func readOptionalConfigValue(env: String, plist: String) -> String? {
        resolveConfigValue(
            env: env,
            plist: plist,
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        ).value
    }

    nonisolated static func resolvedObservabilityStatus(
        environment: [String: String],
        infoDictionary: [String: Any],
        isDebug: Bool
    ) -> ResolvedObservabilityStatus {
        let endpoint = resolveConfigValue(
            env: "UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT",
            plist: "UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT",
            environment: environment,
            infoDictionary: infoDictionary
        )
        let otlpBaseURL = endpoint.value.flatMap { URL(string: $0) }
        let otlpLogsURL = otlpBaseURL.flatMap(normalizedOTLPLogsURL(from:))
        let headers = parseOTLPHeaders(
            raw: resolveConfigValue(
                env: "UNBOUND_OTEL_HEADERS",
                plist: "UNBOUND_OTEL_HEADERS",
                environment: environment,
                infoDictionary: infoDictionary
            ).value
        )
        let mode = resolveObservabilityMode(environment: environment, isDebug: isDebug)

        return ResolvedObservabilityStatus(
            otlpEnabled: otlpBaseURL != nil,
            endpointSource: endpoint.source,
            otlpBaseURL: otlpBaseURL,
            otlpLogsURL: otlpLogsURL,
            headersPresent: !headers.isEmpty,
            headerCount: headers.count,
            mode: mode,
            environment: observabilityEnvironmentName(for: mode),
            infoSampleRate: resolveSampleRate(
                env: "UNBOUND_OBS_INFO_SAMPLE_RATE",
                plist: "UNBOUND_OBS_INFO_SAMPLE_RATE",
                environment: environment,
                infoDictionary: infoDictionary,
                defaultValue: isDebug ? 1.0 : 0.1
            ),
            debugSampleRate: resolveSampleRate(
                env: "UNBOUND_OBS_DEBUG_SAMPLE_RATE",
                plist: "UNBOUND_OBS_DEBUG_SAMPLE_RATE",
                environment: environment,
                infoDictionary: infoDictionary,
                defaultValue: isDebug ? 1.0 : 0.0
            )
        )
    }

    nonisolated static func normalizedOTLPLogsURL(from endpoint: URL) -> URL? {
        let base = endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("/v1/logs") {
            return endpoint
        }
        return URL(string: "\(base)/v1/logs")
    }

    nonisolated private static func resolveOTLPEndpoint(
        environment: [String: String],
        infoDictionary: [String: Any]
    ) -> URL? {
        guard let raw = resolveConfigValue(
            env: "UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT",
            plist: "UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT",
            environment: environment,
            infoDictionary: infoDictionary
        ).value else {
            return nil
        }

        return URL(string: raw)
    }

    nonisolated private static func resolveObservabilityMode(
        environment: [String: String],
        isDebug: Bool
    ) -> ObservabilityMode {
        if let raw = environment["UNBOUND_OBS_MODE"]?
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

    nonisolated private static func observabilityEnvironmentName(for mode: ObservabilityMode) -> String {
        switch mode {
        case .devVerbose:
            return "development"
        case .prodMetadataOnly:
            return "production"
        }
    }

    nonisolated private static func resolveSampleRate(
        env: String,
        plist: String,
        environment: [String: String],
        infoDictionary: [String: Any],
        defaultValue: Double
    ) -> Double {
        guard let raw = resolveConfigValue(
            env: env,
            plist: plist,
            environment: environment,
            infoDictionary: infoDictionary
        ).value,
              let value = Double(raw)
        else {
            return defaultValue
        }

        return min(max(value, 0.0), 1.0)
    }

    nonisolated private static func parseOTLPHeaders(raw: String?) -> [String: String] {
        guard let raw else {
            return [:]
        }

        var headers: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty {
                    headers[key] = value
                }
            }
        }
        return headers
    }

    nonisolated private static func resolveConfigValue(
        env: String,
        plist: String,
        environment: [String: String],
        infoDictionary: [String: Any]
    ) -> ResolvedConfigValue {
        if let value = environment[env]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty
        {
            return ResolvedConfigValue(value: value, source: .env)
        }

        if let value = infoDictionary[plist] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ResolvedConfigValue(value: trimmed, source: .plist)
            }
        }

        return ResolvedConfigValue(value: nil, source: .unset)
    }
}
