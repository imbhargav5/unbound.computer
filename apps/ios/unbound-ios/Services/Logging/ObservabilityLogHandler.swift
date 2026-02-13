import CryptoKit
import Foundation
import Logging

private let observabilityDenylistKeys: [String] = [
    "token",
    "access_token",
    "refresh_token",
    "authorization",
    "cookie",
    "password",
    "secret",
    "private_key",
    "session_secret",
    "apnstoken",
    "pushtoken",
    "content_encrypted",
    "content_nonce"
]

private let observabilityProdAllowedFields: Set<String> = [
    "request_id",
    "session_id",
    "device_id_hash",
    "user_id_hash",
    "trace_id",
    "span_id",
    "app_version",
    "build_version",
    "os_version",
    "component"
]

private let sentryTagKeys: [String] = [
    "runtime",
    "service",
    "component",
    "event_code",
    "request_id",
    "session_id",
    "device_id_hash",
    "user_id_hash",
    "trace_id",
    "span_id"
]

enum ObservabilityService {
    private static let runtimeConfig: ObservabilityRuntimeConfig = {
        ObservabilityRuntimeConfig(
            runtime: "ios",
            service: "ios",
            environment: Config.observabilityEnvironment,
            mode: Config.observabilityMode,
            infoSampleRate: Config.observabilityInfoSampleRate,
            debugSampleRate: Config.observabilityDebugSampleRate,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
    }()

    private static let payloadBuilder = ObservabilityPayloadBuilder(config: runtimeConfig)
    private static let remoteSink = ObservabilityRemoteSink(
        runtimeConfig: runtimeConfig,
        posthogAPIKey: Config.posthogAPIKey,
        posthogHost: Config.posthogHost,
        sentryDSN: Config.sentryDSN
    )

    static func makeHandler(label: String) -> ObservabilityLogHandler? {
        guard let remoteSink else {
            return nil
        }
        return ObservabilityLogHandler(
            label: label,
            payloadBuilder: payloadBuilder,
            remoteSink: remoteSink
        )
    }
}

struct ObservabilityLogHandler: LogHandler {
    let label: String
    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]

    private let payloadBuilder: ObservabilityPayloadBuilder
    private let remoteSink: ObservabilityRemoteSink

    init(
        label: String,
        payloadBuilder: ObservabilityPayloadBuilder,
        remoteSink: ObservabilityRemoteSink
    ) {
        self.label = label
        self.payloadBuilder = payloadBuilder
        self.remoteSink = remoteSink
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata callMetadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        if level < logLevel {
            return
        }

        let rawMessage = message.description
        guard payloadBuilder.shouldSample(level: level, label: label, message: rawMessage) else {
            return
        }

        var mergedMetadata = metadata
        if let callMetadata {
            for (key, value) in callMetadata {
                mergedMetadata[key] = value
            }
        }

        let event = payloadBuilder.build(
            level: level,
            label: label,
            message: rawMessage,
            metadata: mergedMetadata
        )
        remoteSink.export(event)
    }
}

struct ObservabilityRuntimeConfig {
    let runtime: String
    let service: String
    let environment: String
    let mode: ObservabilityMode
    let infoSampleRate: Double
    let debugSampleRate: Double
    let appVersion: String
    let buildVersion: String
    let osVersion: String
}

struct ObservabilityEvent {
    let timestamp: String
    let distinctId: String
    let posthogProperties: [String: Any]
    let sentryLevel: String?
    let sentryMessage: String?
    let sentryTags: [String: String]
}

private struct CorrelationFields {
    let requestId: String?
    let sessionId: String?
    let deviceIdHash: String?
    let userIdHash: String?
    let traceId: String?
    let spanId: String?
}

struct ObservabilityPayloadBuilder {
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let config: ObservabilityRuntimeConfig

    init(config: ObservabilityRuntimeConfig) {
        self.config = config
    }

    func shouldSample(level: Logger.Level, label: String, message: String) -> Bool {
        let rate: Double
        switch level {
        case .trace, .debug:
            rate = config.debugSampleRate
        case .info, .notice:
            rate = config.infoSampleRate
        case .warning, .error, .critical:
            rate = 1.0
        }

        let clampedRate = min(max(rate, 0.0), 1.0)
        if clampedRate >= 1.0 {
            return true
        }
        if clampedRate <= 0.0 {
            return false
        }

        let hashInput = "\(label)|\(level)|\(message)"
        let digest = SHA256.hash(data: Data(hashInput.utf8))
        let value = digest.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt64.self).bigEndian
        }
        let normalized = Double(value) / Double(UInt64.max)
        return normalized < clampedRate
    }

    func build(
        level: Logger.Level,
        label: String,
        message: String,
        metadata: Logger.Metadata
    ) -> ObservabilityEvent {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let metadataObject = convertMetadataToObject(metadata)
        let eventCode = eventCode(from: metadataObject, label: label)
        let component = component(from: metadataObject, label: label)
        let levelValue = uppercaseLevel(level)
        let messageHash = sha256Prefixed(message)

        var properties: [String: Any] = [
            "timestamp": timestamp,
            "runtime": config.runtime,
            "service": config.service,
            "component": component,
            "level": levelValue,
            "event_code": eventCode,
            "environment": config.environment,
            "app_version": config.appVersion,
            "build_version": config.buildVersion,
            "os_version": config.osVersion,
            "message_hash": messageHash
        ]

        switch config.mode {
        case .devVerbose:
            properties["target"] = label
            properties["pid"] = ProcessInfo.processInfo.processIdentifier
            properties["message"] = sanitizeString(message)
            let sanitizedFields = sanitizeObject(metadataObject)
            if !sanitizedFields.isEmpty {
                properties["fields"] = sanitizedFields
            }
        case .prodMetadataOnly:
            for key in observabilityProdAllowedFields {
                if let rawValue = metadataObject[key],
                   let sanitized = sanitizeValue(key: key, value: rawValue)
                {
                    properties[key] = sanitized
                }
            }
        }

        let correlation = extractCorrelationFields(from: metadataObject)
        applyCorrelationFields(correlation, to: &properties)

        let distinctId = readString(properties["device_id_hash"]) ??
            readString(properties["user_id_hash"]) ??
            "\(config.runtime)-\(ProcessInfo.processInfo.processIdentifier)"

        let sentryLevel = sentryLevel(from: level)
        let sentryMessage: String? = sentryLevel == nil ? nil : eventCode
        var sentryTags: [String: String] = [:]
        for key in sentryTagKeys {
            if let value = readString(properties[key]) {
                sentryTags[key] = value
            }
        }

        return ObservabilityEvent(
            timestamp: timestamp,
            distinctId: distinctId,
            posthogProperties: properties,
            sentryLevel: sentryLevel,
            sentryMessage: sentryMessage,
            sentryTags: sentryTags
        )
    }

    private func convertMetadataToObject(_ metadata: Logger.Metadata) -> [String: Any] {
        var object: [String: Any] = [:]
        for (key, value) in metadata {
            if let converted = convertMetadataValue(value) {
                object[key] = converted
            }
        }
        return object
    }

    private func convertMetadataValue(_ value: Logger.Metadata.Value) -> Any? {
        switch value {
        case .string(let string):
            return string
        case .stringConvertible(let stringConvertible):
            return stringConvertible.description
        case .array(let values):
            let converted = values.compactMap(convertMetadataValue(_:))
            return converted.isEmpty ? nil : converted
        case .dictionary(let dictionary):
            var converted: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                if let nested = convertMetadataValue(nestedValue) {
                    converted[key] = nested
                }
            }
            return converted.isEmpty ? nil : converted
        }
    }

    private func eventCode(from metadata: [String: Any], label: String) -> String {
        if let eventCode = readString(metadata["event_code"]), !eventCode.isEmpty {
            return eventCode
        }

        let replaced = String(label
            .map { character -> Character in
                character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) } ? character : "."
            })
        let normalizedLabel = replaced
            .split(separator: ".")
            .joined(separator: ".")
        return "\(config.service).\(normalizedLabel)"
    }

    private func component(from metadata: [String: Any], label: String) -> String {
        if let explicitComponent = readString(metadata["component"]), !explicitComponent.isEmpty {
            return explicitComponent
        }

        let segments = label.split(separator: ".")
        if segments.count >= 2 {
            return String(segments[1])
        }
        return label
    }
}

final class ObservabilityRemoteSink {
    private let runtimeConfig: ObservabilityRuntimeConfig
    private let posthogAPIKey: String?
    private let posthogHost: URL?
    private let sentryDSN: ParsedSentryDSN?
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.unbound.ios.observability.export", qos: .utility)

    init?(
        runtimeConfig: ObservabilityRuntimeConfig,
        posthogAPIKey: String?,
        posthogHost: URL?,
        sentryDSN: String?
    ) {
        let normalizedPosthogKey = posthogAPIKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSentryDSN = sentryDSN?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard (normalizedPosthogKey?.isEmpty == false) || (normalizedSentryDSN?.isEmpty == false) else {
            return nil
        }

        self.runtimeConfig = runtimeConfig
        self.posthogAPIKey = normalizedPosthogKey?.isEmpty == false ? normalizedPosthogKey : nil
        self.posthogHost = posthogHost
        if let normalizedSentryDSN {
            self.sentryDSN = ParsedSentryDSN(rawValue: normalizedSentryDSN)
        } else {
            self.sentryDSN = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: configuration)
    }

    func export(_ event: ObservabilityEvent) {
        queue.async { [runtimeConfig, posthogAPIKey, posthogHost, sentryDSN, session] in
            if let posthogAPIKey, let posthogHost {
                Self.sendToPosthog(
                    event: event,
                    apiKey: posthogAPIKey,
                    host: posthogHost,
                    session: session
                )
            }

            if let sentryDSN, let sentryLevel = event.sentryLevel {
                Self.sendToSentry(
                    event: event,
                    runtimeConfig: runtimeConfig,
                    sentryLevel: sentryLevel,
                    sentryDSN: sentryDSN,
                    session: session
                )
            }
        }
    }

    private static func sendToPosthog(
        event: ObservabilityEvent,
        apiKey: String,
        host: URL,
        session: URLSession
    ) {
        let endpoint = host.appendingPathComponent("batch/")
        let batchEvent: [String: Any] = [
            "event": "app_log",
            "distinct_id": event.distinctId,
            "properties": event.posthogProperties,
            "timestamp": event.timestamp
        ]
        let payload: [String: Any] = [
            "api_key": apiKey,
            "batch": [batchEvent],
            "sent_at": event.timestamp
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payloadData

        session.dataTask(with: request).resume()
    }

    private static func sendToSentry(
        event: ObservabilityEvent,
        runtimeConfig: ObservabilityRuntimeConfig,
        sentryLevel: String,
        sentryDSN: ParsedSentryDSN,
        session: URLSession
    ) {
        var payload: [String: Any] = [
            "event_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            "timestamp": event.timestamp,
            "platform": "cocoa",
            "logger": "app_log",
            "level": sentryLevel,
            "message": event.sentryMessage ?? "observability.remote.error",
            "tags": event.sentryTags,
            "environment": runtimeConfig.environment
        ]

        if runtimeConfig.appVersion != "unknown" || runtimeConfig.buildVersion != "unknown" {
            payload["release"] = "\(runtimeConfig.appVersion)+\(runtimeConfig.buildVersion)"
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(url: sentryDSN.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sentryDSN.authHeader, forHTTPHeaderField: "X-Sentry-Auth")
        request.httpBody = payloadData

        session.dataTask(with: request).resume()
    }
}

private struct ParsedSentryDSN {
    let endpoint: URL
    let authHeader: String

    init?(rawValue: String) {
        guard let dsnURL = URL(string: rawValue),
              let scheme = dsnURL.scheme,
              let host = dsnURL.host,
              let key = dsnURL.user,
              !key.isEmpty else {
            return nil
        }

        let pathParts = dsnURL.path.split(separator: "/")
        guard let projectID = pathParts.last, !projectID.isEmpty else {
            return nil
        }
        let prefix = pathParts.dropLast().joined(separator: "/")

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = dsnURL.port
        if prefix.isEmpty {
            components.path = "/api/\(projectID)/store/"
        } else {
            components.path = "/\(prefix)/api/\(projectID)/store/"
        }

        guard let endpoint = components.url else {
            return nil
        }

        self.endpoint = endpoint
        self.authHeader = "Sentry sentry_version=7, sentry_client=unbound-ios-observability/1.0, sentry_key=\(key)"
    }
}

private func uppercaseLevel(_ level: Logger.Level) -> String {
    switch level {
    case .trace:
        return "TRACE"
    case .debug:
        return "DEBUG"
    case .info:
        return "INFO"
    case .notice:
        return "NOTICE"
    case .warning:
        return "WARN"
    case .error:
        return "ERROR"
    case .critical:
        return "CRITICAL"
    }
}

private func sentryLevel(from level: Logger.Level) -> String? {
    switch level {
    case .warning:
        return "warning"
    case .error:
        return "error"
    case .critical:
        return "fatal"
    default:
        return nil
    }
}

private func sanitizeObject(_ object: [String: Any]) -> [String: Any] {
    var sanitized: [String: Any] = [:]
    for (key, value) in object {
        if let redactedValue = sanitizeValue(key: key, value: value) {
            sanitized[key] = redactedValue
        }
    }
    return sanitized
}

private func sanitizeValue(key: String, value: Any) -> Any? {
    if isSensitiveKey(key) {
        return "[REDACTED]"
    }

    if let stringValue = readString(value) {
        return sanitizeString(stringValue)
    }

    if let dictionaryValue = value as? [String: Any] {
        return sanitizeObject(dictionaryValue)
    }

    if let arrayValue = value as? [Any] {
        let sanitizedArray = arrayValue.compactMap { sanitizeValue(key: key, value: $0) }
        return sanitizedArray
    }

    if let number = value as? NSNumber {
        return number
    }

    if value is NSNull {
        return NSNull()
    }

    return nil
}

private func sanitizeString(_ rawValue: String) -> String {
    if looksLikeSensitiveValue(rawValue) {
        return "[REDACTED]"
    }

    if rawValue.count > 512 {
        return "[TRUNCATED:\(sha256Prefixed(rawValue))]"
    }

    return rawValue
}

private func looksLikeSensitiveValue(_ value: String) -> Bool {
    let lowercased = value.lowercased()
    if lowercased.hasPrefix("bearer ") {
        return true
    }

    if value.split(separator: ".").count == 3 && value.count > 40 {
        return true
    }

    return isLongHex(value) || isLongBase64(value)
}

private func isSensitiveKey(_ key: String) -> Bool {
    let lowercased = key.lowercased()
    return observabilityDenylistKeys.contains { lowercased.contains($0) }
}

private func isLongHex(_ value: String) -> Bool {
    value.count > 48 && value.unicodeScalars.allSatisfy { scalar in
        CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
    }
}

private func isLongBase64(_ value: String) -> Bool {
    value.count > 48 && value.unicodeScalars.allSatisfy { scalar in
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
            .contains(scalar)
    }
}

private func readFirstString(in object: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = readString(object[key]) {
            return value
        }
    }
    return nil
}

private func sanitizeCorrelationString(_ value: String) -> String {
    sanitizeString(value)
}

private func normalizeHashIdentifier(_ value: String) -> String {
    if value.lowercased().hasPrefix("sha256:") {
        return value
    }
    return sha256Prefixed(value)
}

private func extractCorrelationFields(from metadata: [String: Any]) -> CorrelationFields {
    let requestID = readFirstString(in: metadata, keys: ["request_id", "requestId", "request-id"])
        .map(sanitizeCorrelationString(_:))
    let sessionID = readFirstString(in: metadata, keys: ["session_id", "sessionId"])
        .map(sanitizeCorrelationString(_:))
    let traceID = readFirstString(in: metadata, keys: ["trace_id", "traceId"])
        .map(sanitizeCorrelationString(_:))
    let spanID = readFirstString(in: metadata, keys: ["span_id", "spanId"])
        .map(sanitizeCorrelationString(_:))

    let explicitDeviceHash = readFirstString(in: metadata, keys: ["device_id_hash", "deviceIdHash"])
        .map(normalizeHashIdentifier(_:))
    let fallbackDeviceHash = readFirstString(in: metadata, keys: ["device_id", "deviceId"])
        .map(sha256Prefixed(_:))

    let explicitUserHash = readFirstString(in: metadata, keys: ["user_id_hash", "userIdHash"])
        .map(normalizeHashIdentifier(_:))
    let fallbackUserHash = readFirstString(in: metadata, keys: ["user_id", "userId"])
        .map(sha256Prefixed(_:))

    return CorrelationFields(
        requestId: requestID,
        sessionId: sessionID,
        deviceIdHash: explicitDeviceHash ?? fallbackDeviceHash,
        userIdHash: explicitUserHash ?? fallbackUserHash,
        traceId: traceID,
        spanId: spanID
    )
}

private func applyCorrelationFields(_ fields: CorrelationFields, to properties: inout [String: Any]) {
    if let requestId = fields.requestId {
        properties["request_id"] = requestId
    }
    if let sessionId = fields.sessionId {
        properties["session_id"] = sessionId
    }
    if let deviceIdHash = fields.deviceIdHash {
        properties["device_id_hash"] = deviceIdHash
    }
    if let userIdHash = fields.userIdHash {
        properties["user_id_hash"] = userIdHash
    }
    if let traceId = fields.traceId {
        properties["trace_id"] = traceId
    }
    if let spanId = fields.spanId {
        properties["span_id"] = spanId
    }
}

private func readString(_ value: Any?) -> String? {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}

private func sha256Prefixed(_ rawValue: String) -> String {
    let digest = SHA256.hash(data: Data(rawValue.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "sha256:\(hex)"
}
