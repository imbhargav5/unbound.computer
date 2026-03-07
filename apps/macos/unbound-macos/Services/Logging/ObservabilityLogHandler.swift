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

enum ObservabilityService {
    private static let runtimeConfig: ObservabilityRuntimeConfig = {
        ObservabilityRuntimeConfig(
            runtime: "macos",
            service: "macos",
            environment: Config.observabilityEnvironment,
            mode: Config.observabilityMode,
            infoSampleRate: Config.observabilityInfoSampleRate,
            debugSampleRate: Config.observabilityDebugSampleRate,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
    }()

    private static let payloadBuilder = ObservabilityPayloadBuilder(config: runtimeConfig)
    private static let otlpSink = ObservabilityOTLPSink(
        endpoint: Config.otlpEndpoint,
        headers: Config.otlpHeaders,
        config: runtimeConfig
    )

    static func makeHandler(label: String) -> ObservabilityLogHandler? {
        guard let otlpSink else {
            return nil
        }
        return ObservabilityLogHandler(
            label: label,
            payloadBuilder: payloadBuilder,
            sink: otlpSink
        )
    }
}

struct ObservabilityLogHandler: LogHandler {
    let label: String
    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]

    private let payloadBuilder: ObservabilityPayloadBuilder
    private let sink: ObservabilityOTLPSink

    init(
        label: String,
        payloadBuilder: ObservabilityPayloadBuilder,
        sink: ObservabilityOTLPSink
    ) {
        self.label = label
        self.payloadBuilder = payloadBuilder
        self.sink = sink
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

        let record = payloadBuilder.build(
            level: level,
            label: label,
            message: rawMessage,
            metadata: mergedMetadata
        )
        sink.export(record)
    }
}

struct OTLPLogRecord {
    let timeUnixNano: UInt64
    let severityNumber: Int
    let severityText: String
    let body: String
    let scopeName: String
    let attributes: [String: String]
    let traceId: String?
    let spanId: String?
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

private struct CorrelationFields {
    let requestId: String?
    let sessionId: String?
    let deviceIdHash: String?
    let userIdHash: String?
    let traceId: String?
    let spanId: String?
}

struct ObservabilityPayloadBuilder {
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
    ) -> OTLPLogRecord {
        let now = Date()
        let timeUnixNano = UInt64(now.timeIntervalSince1970 * 1_000_000_000)
        let metadataObject = convertMetadataToObject(metadata)
        let eventCode = eventCode(from: metadataObject, label: label)
        let component = component(from: metadataObject, label: label)
        let severityText = otlpSeverityText(level)
        let severityNumber = otlpSeverityNumber(level)
        let messageHash = sha256Prefixed(message)

        var attributes: [String: String] = [
            "runtime": config.runtime,
            "service": config.service,
            "component": component,
            "event_code": eventCode,
            "environment": config.environment,
            "app_version": config.appVersion,
            "build_version": config.buildVersion,
            "os_version": config.osVersion,
            "message_hash": messageHash
        ]

        let body: String

        switch config.mode {
        case .devVerbose:
            attributes["target"] = label
            attributes["pid"] = String(ProcessInfo.processInfo.processIdentifier)
            body = sanitizeString(message)
            let sanitizedFields = sanitizeObject(metadataObject)
            for (key, value) in sanitizedFields {
                if let stringValue = stringifyValue(value) {
                    attributes["fields.\(key)"] = stringValue
                }
            }
        case .prodMetadataOnly:
            body = eventCode
            for key in observabilityProdAllowedFields {
                if let rawValue = metadataObject[key],
                   let sanitized = sanitizeValue(key: key, value: rawValue),
                   let stringValue = stringifyValue(sanitized)
                {
                    attributes[key] = stringValue
                }
            }
        }

        let correlation = extractCorrelationFields(from: metadataObject)
        if let requestId = correlation.requestId {
            attributes["request_id"] = requestId
        }
        if let sessionId = correlation.sessionId {
            attributes["session_id"] = sessionId
        }
        if let deviceIdHash = correlation.deviceIdHash {
            attributes["device_id_hash"] = deviceIdHash
        }
        if let userIdHash = correlation.userIdHash {
            attributes["user_id_hash"] = userIdHash
        }

        return OTLPLogRecord(
            timeUnixNano: timeUnixNano,
            severityNumber: severityNumber,
            severityText: severityText,
            body: body,
            scopeName: label,
            attributes: attributes,
            traceId: correlation.traceId,
            spanId: correlation.spanId
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

// MARK: - OTLP Sink

final class ObservabilityOTLPSink {
    private let endpoint: URL
    private let headers: [String: String]
    private let resourceAttributes: [[String: Any]]
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.unbound.macos.observability.otlp", qos: .utility)
    private var buffer: [OTLPLogRecord] = []
    private var flushTimer: DispatchSourceTimer?

    private static let maxBatchSize = 100
    private static let flushIntervalSeconds: Double = 5.0

    init?(
        endpoint: URL?,
        headers: [String: String],
        config: ObservabilityRuntimeConfig
    ) {
        guard let endpoint else { return nil }

        let base = endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("/v1/logs") {
            self.endpoint = endpoint
        } else {
            guard let logsURL = URL(string: "\(base)/v1/logs") else { return nil }
            self.endpoint = logsURL
        }

        self.headers = headers
        self.resourceAttributes = Self.buildResourceAttributes(config: config)

        let urlConfig = URLSessionConfiguration.ephemeral
        urlConfig.timeoutIntervalForRequest = 10
        urlConfig.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: urlConfig)

        startFlushTimer()
    }

    func export(_ record: OTLPLogRecord) {
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(record)
            if self.buffer.count >= Self.maxBatchSize {
                self.performFlush()
            }
        }
    }

    func flush() {
        queue.async { [weak self] in
            self?.performFlush()
        }
    }

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Self.flushIntervalSeconds,
            repeating: Self.flushIntervalSeconds
        )
        timer.setEventHandler { [weak self] in
            self?.performFlush()
        }
        timer.resume()
        flushTimer = timer
    }

    private func performFlush() {
        guard !buffer.isEmpty else { return }
        let records = buffer
        buffer = []

        // Group log records by scope for a compact payload
        var scopeGroups: [String: [[String: Any]]] = [:]
        for record in records {
            let logRecordJSON = buildLogRecordJSON(record)
            scopeGroups[record.scopeName, default: []].append(logRecordJSON)
        }

        let scopeLogs: [[String: Any]] = scopeGroups.map { scopeName, logRecords in
            [
                "scope": ["name": scopeName],
                "logRecords": logRecords
            ]
        }

        let payload: [String: Any] = [
            "resourceLogs": [[
                "resource": ["attributes": resourceAttributes],
                "scopeLogs": scopeLogs
            ]]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = data

        session.dataTask(with: request).resume()
    }

    private func buildLogRecordJSON(_ record: OTLPLogRecord) -> [String: Any] {
        let attributes: [[String: Any]] = record.attributes.map { key, value in
            ["key": key, "value": ["stringValue": value]]
        }

        return [
            "timeUnixNano": String(record.timeUnixNano),
            "severityNumber": record.severityNumber,
            "severityText": record.severityText,
            "body": ["stringValue": record.body],
            "attributes": attributes,
            "traceId": record.traceId ?? "",
            "spanId": record.spanId ?? ""
        ]
    }

    private static func buildResourceAttributes(config: ObservabilityRuntimeConfig) -> [[String: Any]] {
        [
            ["key": "service.name", "value": ["stringValue": config.service]],
            ["key": "service.namespace", "value": ["stringValue": "unbound"]],
            ["key": "deployment.environment", "value": ["stringValue": config.environment]],
            ["key": "telemetry.sdk.language", "value": ["stringValue": "swift"]],
            ["key": "app.version", "value": ["stringValue": config.appVersion]],
            ["key": "build.version", "value": ["stringValue": config.buildVersion]],
            ["key": "os.version", "value": ["stringValue": config.osVersion]]
        ]
    }
}

// MARK: - OTLP Severity Mapping

private func otlpSeverityNumber(_ level: Logger.Level) -> Int {
    switch level {
    case .trace:
        return 1
    case .debug:
        return 5
    case .info:
        return 9
    case .notice:
        return 10
    case .warning:
        return 13
    case .error:
        return 17
    case .critical:
        return 21
    }
}

private func otlpSeverityText(_ level: Logger.Level) -> String {
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

// MARK: - Sanitization Helpers

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

// MARK: - Correlation Helpers

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

// MARK: - Value Helpers

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

private func stringifyValue(_ value: Any) -> String? {
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    if JSONSerialization.isValidJSONObject([value]),
       let data = try? JSONSerialization.data(withJSONObject: value),
       let s = String(data: data, encoding: .utf8)
    {
        return s
    }
    return nil
}

private func sha256Prefixed(_ rawValue: String) -> String {
    let digest = SHA256.hash(data: Data(rawValue.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "sha256:\(hex)"
}
