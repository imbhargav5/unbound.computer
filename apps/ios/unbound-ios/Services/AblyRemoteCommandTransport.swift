//
//  AblyRemoteCommandTransport.swift
//  unbound-ios
//
//  Ably transport for UM secret-sharing remote command flow.
//

import Foundation
import Logging

#if canImport(Ably)
import Ably
#endif

private let ablyRemoteLogger = Logger(label: "app.ably.remote")

enum RemoteCommandTransportError: Error, LocalizedError {
    case notConfigured
    case authFailed(String)
    case timeout
    case publishFailed(String)
    case invalidMessageData
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Ably auth is not configured"
        case .authFailed(let message):
            return "Ably token auth failed: \(message)"
        case .timeout:
            return "Timed out waiting for remote command response"
        case .publishFailed(let message):
            return "Failed to publish remote command: \(message)"
        case .invalidMessageData:
            return "Invalid message data received from Ably"
        case .unsupportedPlatform:
            return "Ably SDK is unavailable in this build"
        }
    }
}

struct RemoteCommandAckEnvelope: Codable {
    let schemaVersion: Int
    let commandId: String
    let status: String
    let createdAtMs: Int64
    let resultB64: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case commandId = "command_id"
        case status
        case createdAtMs = "created_at_ms"
        case resultB64 = "result_b64"
    }
}

struct RemoteCommandDecisionResult: Codable {
    let schemaVersion: Int
    let requestId: String?
    let sessionId: String?
    let status: String
    let reasonCode: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case sessionId = "session_id"
        case status
        case reasonCode = "reason_code"
        case message
    }
}

struct UMSecretRequestCommandPayload: Codable {
    let type: String
    let requestId: String
    let sessionId: String
    let requesterDeviceId: String
    let targetDeviceId: String
    let requestedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case type
        case requestId = "request_id"
        case sessionId = "session_id"
        case requesterDeviceId = "requester_device_id"
        case targetDeviceId = "target_device_id"
        case requestedAtMs = "requested_at_ms"
    }
}

struct SessionSecretResponseEnvelope: Codable {
    let schemaVersion: Int
    let requestId: String
    let sessionId: String
    let senderDeviceId: String
    let receiverDeviceId: String
    let status: String
    let errorCode: String?
    let ciphertextB64: String?
    let encapsulationPubkeyB64: String?
    let nonceB64: String?
    let algorithm: String
    let createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case sessionId = "session_id"
        case senderDeviceId = "sender_device_id"
        case receiverDeviceId = "receiver_device_id"
        case status
        case errorCode = "error_code"
        case ciphertextB64 = "ciphertext_b64"
        case encapsulationPubkeyB64 = "encapsulation_pubkey_b64"
        case nonceB64 = "nonce_b64"
        case algorithm
        case createdAtMs = "created_at_ms"
    }
}

/// Generic remote command envelope sent from iOS to daemon via Ably.
struct RemoteCommandEnvelope: Codable {
    let schemaVersion: Int
    let type: String
    let requestId: String
    let requesterDeviceId: String
    let targetDeviceId: String
    let requestedAtMs: Int64
    let params: [String: AnyCodableValue]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case type
        case requestId = "request_id"
        case requesterDeviceId = "requester_device_id"
        case targetDeviceId = "target_device_id"
        case requestedAtMs = "requested_at_ms"
        case params
    }
}

/// Response envelope published by daemon back to iOS via Falco.
struct RemoteCommandResponse: Codable {
    let schemaVersion: Int
    let requestId: String
    let type: String
    let status: String
    let result: AnyCodableValue?
    let errorCode: String?
    let errorMessage: String?
    let errorData: AnyCodableValue?
    let createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case type
        case status
        case result
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case errorData = "error_data"
        case createdAtMs = "created_at_ms"
    }

    init(
        schemaVersion: Int,
        requestId: String,
        type: String,
        status: String,
        result: AnyCodableValue?,
        errorCode: String?,
        errorMessage: String?,
        errorData: AnyCodableValue? = nil,
        createdAtMs: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.type = type
        self.status = status
        self.result = result
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.errorData = errorData
        self.createdAtMs = createdAtMs
    }

    var isOk: Bool { status == "ok" }
}

/// Type-erased JSON value for encoding/decoding arbitrary command params and results.
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Access as a dictionary for result parsing.
    var objectValue: [String: AnyCodableValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    /// Access as a string.
    var stringValue: String? {
        if case .string(let str) = self { return str }
        return nil
    }

    /// Access as an integer.
    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    /// Access as a boolean.
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Access as an array.
    var arrayValue: [AnyCodableValue]? {
        if case .array(let values) = self { return values }
        return nil
    }
}

protocol RemoteCommandTransport {
    func publishRemoteCommand(
        channel: String,
        payload: UMSecretRequestCommandPayload
    ) async throws

    func waitForAck(
        channel: String,
        requestId: String,
        timeout: TimeInterval
    ) async throws -> RemoteCommandAckEnvelope

    func waitForSessionSecretResponse(
        channel: String,
        requestId: String,
        sessionId: String,
        timeout: TimeInterval
    ) async throws -> SessionSecretResponseEnvelope

    /// Publish a generic remote command envelope.
    func publishGenericCommand(
        channel: String,
        envelope: RemoteCommandEnvelope
    ) async throws

    /// Wait for a remote command response matching the given requestId.
    func waitForCommandResponse(
        channel: String,
        requestId: String,
        timeout: TimeInterval
    ) async throws -> RemoteCommandResponse
}

final class AblyRemoteCommandTransport: RemoteCommandTransport {
    #if canImport(Ably)
    private let realtime: ARTRealtime?
    #endif

    init(
        tokenAuthURL: URL = Config.ablyTokenAuthURL,
        authService: AuthService = .shared,
        keychainService: KeychainService = .shared
    ) {
        #if canImport(Ably)
        let resolvedTokenAuthURL = tokenAuthURL
        let resolvedAuthService = authService
        let resolvedKeychainService = keychainService
        let options = ARTClientOptions()
        options.autoConnect = true
        options.authCallback = { _, callback in
            Self.fetchTokenDetails(
                tokenAuthURL: resolvedTokenAuthURL,
                authService: resolvedAuthService,
                keychainService: resolvedKeychainService,
                callback: callback
            )
        }
        self.realtime = ARTRealtime(options: options)
        ablyRemoteLogger.info("Ably realtime transport initialized with token auth")
        #endif
    }

    deinit {
        #if canImport(Ably)
        realtime?.close()
        #endif
    }

    func publishRemoteCommand(
        channel: String,
        payload: UMSecretRequestCommandPayload
    ) async throws {
        #if canImport(Ably)
        let realtime = try requireRealtime()
        let channelRef = realtime.channels.get(channel)
        ablyRemoteLogger.debug(
            "Publishing remote command on channel=\(channel), request_id=\(payload.requestId)"
        )
        let payloadData = try JSONEncoder().encode(payload)
        let payloadObject = try jsonObject(from: payloadData)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channelRef.publish(Config.remoteCommandEventName, data: payloadObject) { error in
                if let error {
                    ablyRemoteLogger.error(
                        "Failed to publish remote command request_id=\(payload.requestId): \(error.message)"
                    )
                    continuation.resume(throwing: RemoteCommandTransportError.publishFailed(error.message))
                    return
                }
                ablyRemoteLogger.debug(
                    "Published remote command request_id=\(payload.requestId)"
                )
                continuation.resume()
            }
        }
        #else
        throw RemoteCommandTransportError.unsupportedPlatform
        #endif
    }

    func waitForAck(
        channel: String,
        requestId: String,
        timeout: TimeInterval
    ) async throws -> RemoteCommandAckEnvelope {
        ablyRemoteLogger.debug(
            "Waiting for remote ACK on channel=\(channel), request_id=\(requestId)"
        )
        let ack: RemoteCommandAckEnvelope = try await waitForMessage(
            channel: channel,
            eventName: Config.remoteCommandAckEventName,
            timeout: timeout
        ) { (ack: RemoteCommandAckEnvelope) in
            guard let resultB64 = ack.resultB64 else {
                ablyRemoteLogger.debug(
                    "Ignoring ACK without result_b64 on channel=\(channel), command_id=\(ack.commandId)"
                )
                return false
            }
            guard let resultData = Data(base64Encoded: resultB64),
                  let decision = try? JSONDecoder().decode(RemoteCommandDecisionResult.self, from: resultData) else {
                ablyRemoteLogger.debug(
                    "Ignoring ACK with undecodable decision on channel=\(channel), command_id=\(ack.commandId)"
                )
                return false
            }
            guard decision.requestId == requestId else {
                ablyRemoteLogger.debug(
                    "Ignoring ACK request_id mismatch expected=\(requestId), actual=\(decision.requestId ?? "nil")"
                )
                return false
            }
            return decision.requestId == requestId
        }
        ablyRemoteLogger.info(
            "Received remote ACK request_id=\(requestId), status=\(ack.status)"
        )
        return ack
    }

    func waitForSessionSecretResponse(
        channel: String,
        requestId: String,
        sessionId: String,
        timeout: TimeInterval
    ) async throws -> SessionSecretResponseEnvelope {
        ablyRemoteLogger.debug(
            "Waiting for session secret response on channel=\(channel), request_id=\(requestId), session_id=\(sessionId)"
        )
        let response: SessionSecretResponseEnvelope = try await waitForMessage(
            channel: channel,
            eventName: Config.sessionSecretResponseEventName,
            timeout: timeout
        ) { (response: SessionSecretResponseEnvelope) in
            response.requestId == requestId && response.sessionId == sessionId
        }
        ablyRemoteLogger.info(
            "Received session secret response request_id=\(requestId), status=\(response.status)"
        )
        return response
    }

    func publishGenericCommand(
        channel: String,
        envelope: RemoteCommandEnvelope
    ) async throws {
        #if canImport(Ably)
        let realtime = try requireRealtime()
        let channelRef = realtime.channels.get(channel)
        ablyRemoteLogger.debug(
            "Publishing generic command on channel=\(channel), type=\(envelope.type), request_id=\(envelope.requestId)"
        )
        let payloadData = try JSONEncoder().encode(envelope)
        let payloadObject = try jsonObject(from: payloadData)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channelRef.publish(Config.remoteCommandEventName, data: payloadObject) { error in
                if let error {
                    ablyRemoteLogger.error(
                        "Failed to publish generic command request_id=\(envelope.requestId): \(error.message)"
                    )
                    continuation.resume(throwing: RemoteCommandTransportError.publishFailed(error.message))
                    return
                }
                ablyRemoteLogger.debug(
                    "Published generic command request_id=\(envelope.requestId)"
                )
                continuation.resume()
            }
        }
        #else
        throw RemoteCommandTransportError.unsupportedPlatform
        #endif
    }

    func waitForCommandResponse(
        channel: String,
        requestId: String,
        timeout: TimeInterval
    ) async throws -> RemoteCommandResponse {
        ablyRemoteLogger.debug(
            "Waiting for command response on channel=\(channel), request_id=\(requestId)"
        )
        let response: RemoteCommandResponse = try await waitForMessage(
            channel: channel,
            eventName: Config.remoteCommandResponseEventName,
            timeout: timeout
        ) { (response: RemoteCommandResponse) in
            response.requestId == requestId
        }
        ablyRemoteLogger.info(
            "Received command response request_id=\(requestId), type=\(response.type), status=\(response.status)"
        )
        return response
    }

    #if canImport(Ably)
    private func requireRealtime() throws -> ARTRealtime {
        guard let realtime else {
            ablyRemoteLogger.error("Ably realtime unavailable: client not initialized")
            throw RemoteCommandTransportError.notConfigured
        }
        return realtime
    }

    private struct TokenRequestBody: Encodable {
        let deviceId: String

        enum CodingKeys: String, CodingKey {
            case deviceId = "deviceId"
        }
    }

    private struct TokenDetailsPayload: Decodable {
        let token: String
        let expires: Int64?
        let issued: Int64?
        let capability: String?
        let clientId: String?

        enum CodingKeys: String, CodingKey {
            case token
            case expires
            case issued
            case capability
            case clientId = "clientId"
        }
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let details: String?
    }

    private static func fetchTokenDetails(
        tokenAuthURL: URL,
        authService: AuthService,
        keychainService: KeychainService,
        callback: @escaping ARTTokenDetailsCompatibleCallback
    ) {
        Task {
            do {
                let tokenDetails = try await requestTokenDetails(
                    tokenAuthURL: tokenAuthURL,
                    authService: authService,
                    keychainService: keychainService
                )
                ablyRemoteLogger.debug("Fetched Ably token details from mobile API")
                callback(tokenDetails, nil)
            } catch {
                let transportError = mapTokenAuthError(error)
                ablyRemoteLogger.error("Failed to fetch Ably token details: \(transportError.localizedDescription)")
                callback(nil, transportError.asNSError())
            }
        }
    }

    private static func requestTokenDetails(
        tokenAuthURL: URL,
        authService: AuthService,
        keychainService: KeychainService
    ) async throws -> ARTTokenDetails {
        let resolvedUserId = authService.currentUserId ?? (try? keychainService.getSupabaseUserId())
        guard let userId = resolvedUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
            throw RemoteCommandTransportError.authFailed("User is not authenticated")
        }

        let deviceId: UUID
        do {
            deviceId = try keychainService.getDeviceId(forUser: userId)
        } catch {
            throw RemoteCommandTransportError.authFailed("Device ID is not available in keychain")
        }

        let accessToken: String
        do {
            accessToken = try await authService.getAccessToken()
        } catch {
            throw RemoteCommandTransportError.authFailed("Unable to obtain access token")
        }

        var request = URLRequest(url: tokenAuthURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            TokenRequestBody(deviceId: deviceId.uuidString.lowercased())
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteCommandTransportError.authFailed("Token auth server returned invalid response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = Self.decodeServerErrorMessage(from: data)
            throw RemoteCommandTransportError.authFailed(
                "Token endpoint returned HTTP \(httpResponse.statusCode): \(errorMessage)"
            )
        }

        let payload: TokenDetailsPayload
        do {
            payload = try JSONDecoder().decode(TokenDetailsPayload.self, from: data)
        } catch {
            throw RemoteCommandTransportError.authFailed("Token endpoint returned invalid payload")
        }

        guard !payload.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteCommandTransportError.authFailed("Token endpoint returned empty token")
        }

        let expiresDate = payload.expires.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        let issuedDate = payload.issued.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        return ARTTokenDetails(
            token: payload.token,
            expires: expiresDate,
            issued: issuedDate,
            capability: payload.capability,
            clientId: payload.clientId
        )
    }

    private static func decodeServerErrorMessage(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            if let error = payload.error, !error.isEmpty {
                return error
            }
            if let details = payload.details, !details.isEmpty {
                return details
            }
        }

        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return raw
        }

        return "Unknown error"
    }

    private static func mapTokenAuthError(_ error: Error) -> RemoteCommandTransportError {
        if let transportError = error as? RemoteCommandTransportError {
            return transportError
        }
        return RemoteCommandTransportError.authFailed(error.localizedDescription)
    }

    private func waitForMessage<T: Decodable>(
        channel: String,
        eventName: String,
        timeout: TimeInterval,
        predicate: @escaping (T) -> Bool
    ) async throws -> T {
        let realtime = try requireRealtime()
        let channelRef = realtime.channels.get(channel)
        ablyRemoteLogger.debug(
            "Subscribing to event=\(eventName) on channel=\(channel) with timeout=\(timeout)"
        )

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = ContinuationGate(continuation)

            var listener: ARTEventListener?
            listener = channelRef.subscribe(eventName) { message in
                do {
                    guard let decoded: T = try Self.decodeMessageData(message.data) else {
                        return
                    }
                    guard predicate(decoded) else { return }
                    if let listener {
                        channelRef.unsubscribe(listener)
                    }
                    gate.resume(returning: decoded)
                } catch {
                    if let listener {
                        channelRef.unsubscribe(listener)
                    }
                    ablyRemoteLogger.error(
                        "Failed decoding Ably message event=\(eventName), channel=\(channel): \(error.localizedDescription)"
                    )
                    gate.resume(throwing: error)
                }
            }

            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let listener {
                    channelRef.unsubscribe(listener)
                }
                ablyRemoteLogger.warning(
                    "Timed out waiting for event=\(eventName), channel=\(channel)"
                )
                gate.resume(throwing: RemoteCommandTransportError.timeout)
            }
        }
    }

    private func jsonObject(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    private static func decodeMessageData<T: Decodable>(_ data: Any?) throws -> T? {
        guard let data else { return nil }

        if let typed = data as? T {
            return typed
        }
        if let rawData = data as? Data {
            return try JSONDecoder().decode(T.self, from: rawData)
        }
        if let rawString = data as? String {
            guard let rawData = rawString.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(T.self, from: rawData)
        }
        if JSONSerialization.isValidJSONObject(data) {
            let rawData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(T.self, from: rawData)
        }

        throw RemoteCommandTransportError.invalidMessageData
    }
    #endif
}

#if canImport(Ably)
extension AblyRemoteCommandTransport {
    static func fetchRealtimeTokenDetails(
        tokenAuthURL: URL = Config.ablyTokenAuthURL,
        authService: AuthService = .shared,
        keychainService: KeychainService = .shared
    ) async throws -> ARTTokenDetails {
        try await requestTokenDetails(
            tokenAuthURL: tokenAuthURL,
            authService: authService,
            keychainService: keychainService
        )
    }

    static func tokenAuthNSError(_ error: Error) -> NSError {
        mapTokenAuthError(error).asNSError()
    }
}
#endif

private extension RemoteCommandTransportError {
    func asNSError() -> NSError {
        NSError(
            domain: "com.unbound.ios.ably",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: localizedDescription]
        )
    }
}

private final class ContinuationGate<T> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }
}
