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

enum OTLPSamplerOverride: Equatable {
    case alwaysOn
    case parentBasedTraceIdRatio(Double)

    nonisolated var identifier: String {
        switch self {
        case .alwaysOn:
            return "always_on"
        case .parentBasedTraceIdRatio:
            return "parentbased_traceidratio"
        }
    }

    nonisolated var ratio: Double? {
        switch self {
        case .alwaysOn:
            return nil
        case let .parentBasedTraceIdRatio(value):
            return value
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
    let traceSampler: String
    let traceSamplerSource: ConfigValueSource
    let traceSamplerArg: Double?
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
            "otlp_trace_sampler": .string(traceSampler),
            "otlp_trace_sampler_source": .string(traceSamplerSource.rawValue),
            "observability_info_sample_rate": .stringConvertible(infoSampleRate),
            "observability_debug_sample_rate": .stringConvertible(debugSampleRate)
        ]

        if let otlpBaseURL {
            metadata["otlp_base_url"] = .string(otlpBaseURL.absoluteString)
        }

        if let otlpLogsURL {
            metadata["otlp_logs_url"] = .string(otlpLogsURL.absoluteString)
        }
        if let traceSamplerArg {
            metadata["otlp_trace_sampler_arg"] = .stringConvertible(traceSamplerArg)
        }

        return metadata
    }
}

enum Config {
    private static let defaultDevTraceRatio = 1.0
    private static let defaultProdTraceRatio = 0.05

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
            infoDictionary: Bundle.main.infoDictionary ?? [:],
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

    static var otlpSamplerOverride: OTLPSamplerOverride? {
        resolveEffectiveTraceSampler(
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            isDebug: isDebug
        ).override
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
        let mode = resolveObservabilityMode(
            environment: environment,
            infoDictionary: infoDictionary,
            isDebug: isDebug
        )
        let effectiveTraceSampler = resolveEffectiveTraceSampler(
            environment: environment,
            infoDictionary: infoDictionary,
            isDebug: isDebug
        )

        return ResolvedObservabilityStatus(
            otlpEnabled: otlpBaseURL != nil,
            endpointSource: endpoint.source,
            otlpBaseURL: otlpBaseURL,
            otlpLogsURL: otlpLogsURL,
            headersPresent: !headers.isEmpty,
            headerCount: headers.count,
            mode: mode,
            environment: observabilityEnvironmentName(for: mode),
            traceSampler: effectiveTraceSampler.name,
            traceSamplerSource: effectiveTraceSampler.source,
            traceSamplerArg: effectiveTraceSampler.arg,
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
        infoDictionary: [String: Any],
        isDebug: Bool
    ) -> ObservabilityMode {
        if let raw = resolveConfigValue(
            env: "UNBOUND_OBS_MODE",
            plist: "UNBOUND_OBS_MODE",
            environment: environment,
            infoDictionary: infoDictionary
        ).value?.lowercased() {
            if raw == "prod" || raw == "production" {
                return .prodMetadataOnly
            }
            if raw == "dev" || raw == "development" {
                return .devVerbose
            }
        }

        if let raw = resolveConfigValue(
            env: "UNBOUND_ENV",
            plist: "UNBOUND_ENV",
            environment: environment,
            infoDictionary: infoDictionary
        ).value?.lowercased() {
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

    nonisolated private static func resolveEffectiveTraceSampler(
        environment: [String: String],
        infoDictionary: [String: Any],
        isDebug: Bool
    ) -> (override: OTLPSamplerOverride?, name: String, source: ConfigValueSource, arg: Double?) {
        let mode = resolveObservabilityMode(
            environment: environment,
            infoDictionary: infoDictionary,
            isDebug: isDebug
        )
        let defaultRatio = switch mode {
        case .devVerbose:
            defaultDevTraceRatio
        case .prodMetadataOnly:
            defaultProdTraceRatio
        }

        let samplerValue = resolveConfigValue(
            env: "UNBOUND_OTEL_SAMPLER",
            plist: "UNBOUND_OTEL_SAMPLER",
            environment: environment,
            infoDictionary: infoDictionary
        )
        let samplerArg = resolveSampleRate(
            env: "UNBOUND_OTEL_TRACES_SAMPLER_ARG",
            plist: "UNBOUND_OTEL_TRACES_SAMPLER_ARG",
            environment: environment,
            infoDictionary: infoDictionary,
            defaultValue: defaultRatio
        )

        guard let rawSampler = samplerValue.value?.lowercased() else {
            switch mode {
            case .devVerbose:
                return (nil, "always_on", .unset, nil)
            case .prodMetadataOnly:
                return (nil, "parentbased_traceidratio", .unset, defaultRatio)
            }
        }

        switch rawSampler {
        case "always_on":
            return (.alwaysOn, "always_on", samplerValue.source, nil)
        case "parentbased_traceidratio":
            return (
                .parentBasedTraceIdRatio(samplerArg),
                "parentbased_traceidratio",
                samplerValue.source,
                samplerArg
            )
        default:
            switch mode {
            case .devVerbose:
                return (nil, "always_on", .unset, nil)
            case .prodMetadataOnly:
                return (nil, "parentbased_traceidratio", .unset, defaultRatio)
            }
        }
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
