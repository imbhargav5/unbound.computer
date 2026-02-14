//
//  AblyRuntimeStatusService.swift
//  unbound-ios
//
//  Ably LiveObjects subscription service for coding session runtime status.
//

import Foundation
import Logging

#if canImport(Ably)
import Ably
import _AblyPluginSupportPrivate
#endif

private let ablyRuntimeStatusLogger = Logger(label: "app.ably.runtime-status")

enum SessionDetailRuntimeStatusServiceError: Error, LocalizedError {
    case notConfigured
    case invalidPayload
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Ably runtime status subscription is not configured"
        case .invalidPayload:
            return "Ably runtime status payload was invalid"
        case .unsupportedPlatform:
            return "Ably runtime status subscription is unavailable in this build"
        }
    }
}

enum SessionDetailRuntimeStatus: String, Codable, CaseIterable {
    case running
    case idle
    case waiting
    case notAvailable = "not-available"
    case error

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = SessionDetailRuntimeStatus(rawValue: raw) ?? .notAvailable
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .running:
            return "Running"
        case .idle:
            return "Idle"
        case .waiting:
            return "Waiting"
        case .notAvailable:
            return "Not Available"
        case .error:
            return "Error"
        }
    }
}

struct SessionDetailRuntimeState: Codable, Equatable {
    let status: SessionDetailRuntimeStatus
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case status
        case errorMessage = "error_message"
    }
}

struct SessionDetailRuntimeStatusEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let codingSession: SessionDetailRuntimeState
    let deviceId: String
    let sessionId: String
    let updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case codingSession = "coding_session"
        case deviceId = "device_id"
        case sessionId = "session_id"
        case updatedAtMs = "updated_at_ms"
    }

    var normalizedSessionId: String {
        sessionId.lowercased()
    }

    var normalizedDeviceId: String {
        deviceId.lowercased()
    }

    var normalizedErrorMessage: String? {
        guard let errorMessage = codingSession.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !errorMessage.isEmpty else {
            return nil
        }
        return errorMessage
    }

    static func decodeEnvelopePayload(_ data: Any?) throws -> SessionDetailRuntimeStatusEnvelope? {
        guard let data else { return nil }

        if let typed = data as? SessionDetailRuntimeStatusEnvelope {
            return typed
        }
        if let rawData = data as? Data {
            return try JSONDecoder().decode(SessionDetailRuntimeStatusEnvelope.self, from: rawData)
        }
        if let rawString = data as? String {
            guard let rawData = rawString.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(SessionDetailRuntimeStatusEnvelope.self, from: rawData)
        }
        if JSONSerialization.isValidJSONObject(data) {
            let rawData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(SessionDetailRuntimeStatusEnvelope.self, from: rawData)
        }

        throw SessionDetailRuntimeStatusServiceError.invalidPayload
    }

    static func decodeFromLiveObjectMessage(
        _ serialized: [String: Any],
        expectedObjectKey: String
    ) -> SessionDetailRuntimeStatusEnvelope? {
        if let name = serialized["name"] as? String,
           name.lowercased() != expectedObjectKey.lowercased() {
            return nil
        }

        let candidates: [Any?] = [
            serialized["value"],
            serialized["data"],
            serialized["object"],
            serialized["state"],
            serialized
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            if let decoded = try? decodeEnvelopePayload(candidate) {
                return decoded
            }
        }

        return nil
    }
}

protocol SessionDetailRuntimeStatusStreaming {
    func subscribe(sessionId: UUID) -> AsyncThrowingStream<SessionDetailRuntimeStatusEnvelope, Error>
}

final class AblyRuntimeStatusService: SessionDetailRuntimeStatusStreaming {
    #if canImport(Ably)
    private let realtime: ARTRealtime?
    private let dispatcher = RuntimeStatusLiveObjectsPlugin.dispatcher
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
        options.plugins = [ARTPluginName.liveObjects: RuntimeStatusLiveObjectsPlugin.self]
        options.authCallback = { _, callback in
            Task {
                do {
                    let tokenDetails = try await AblyRemoteCommandTransport.fetchRealtimeTokenDetails(
                        tokenAuthURL: resolvedTokenAuthURL,
                        authService: resolvedAuthService,
                        keychainService: resolvedKeychainService
                    )
                    callback(tokenDetails, nil)
                } catch {
                    callback(nil, AblyRemoteCommandTransport.tokenAuthNSError(error))
                }
            }
        }
        realtime = ARTRealtime(options: options)
        #endif
    }

    deinit {
        #if canImport(Ably)
        realtime?.close()
        #endif
    }

    func subscribe(sessionId: UUID) -> AsyncThrowingStream<SessionDetailRuntimeStatusEnvelope, Error> {
        #if canImport(Ably)
        AsyncThrowingStream { continuation in
            guard let realtime else {
                continuation.finish(throwing: SessionDetailRuntimeStatusServiceError.notConfigured)
                return
            }

            let expectedSessionId = sessionId.uuidString.lowercased()
            let channelName = Config.runtimeStatusChannel(sessionId: sessionId)
            let channelOptions = ARTRealtimeChannelOptions()
            channelOptions.modes = [.subscribe, .objectSubscribe]
            let channelRef = realtime.channels.get(channelName, options: channelOptions)

            let listenerId = dispatcher.register(channelName: channelName) { envelope in
                guard envelope.normalizedSessionId == expectedSessionId else {
                    ablyRuntimeStatusLogger.debug(
                        "Ignoring runtime status payload for mismatched session expected=\(expectedSessionId), actual=\(envelope.normalizedSessionId)"
                    )
                    return
                }
                continuation.yield(envelope)
            }

            channelRef.attach { error in
                guard let error else { return }
                continuation.finish(throwing: error)
            }

            continuation.onTermination = { _ in
                Task { @MainActor in
                    self.dispatcher.unregister(listenerId)
                }
                channelRef.detach()
            }
        }
        #else
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: SessionDetailRuntimeStatusServiceError.unsupportedPlatform)
        }
        #endif
    }
}

#if canImport(Ably)
private final class RuntimeStatusObjectMessage: NSObject, ObjectMessageProtocol {
    let serialized: [String: Any]

    init(serialized: [String: Any]) {
        self.serialized = serialized
    }
}

private final class RuntimeStatusLiveObjectsPlugin: NSObject, LiveObjectsPluginProtocol {
    static let dispatcher = RuntimeStatusLiveObjectsDispatcher()
    private static let internalPluginInstance = RuntimeStatusLiveObjectsInternalPlugin(dispatcher: dispatcher)

    static func internalPlugin() -> any LiveObjectsInternalPluginProtocol {
        internalPluginInstance
    }
}

private final class RuntimeStatusLiveObjectsInternalPlugin: NSObject, LiveObjectsInternalPluginProtocol {
    private let dispatcher: RuntimeStatusLiveObjectsDispatcher

    init(dispatcher: RuntimeStatusLiveObjectsDispatcher) {
        self.dispatcher = dispatcher
    }

    func nosync_prepare(_ channel: any RealtimeChannel, client: any RealtimeClient) {
        // No-op: runtime status subscriptions are handled by service-level listeners.
    }

    func decodeObjectMessage(
        _ serialized: [String: Any],
        context _: any DecodingContextProtocol,
        format _: EncodingFormat,
        error _: AutoreleasingUnsafeMutablePointer<(any PublicErrorInfo)?>?
    ) -> (any ObjectMessageProtocol)? {
        RuntimeStatusObjectMessage(serialized: serialized)
    }

    func encodeObjectMessage(
        _ objectMessage: any ObjectMessageProtocol,
        format _: EncodingFormat
    ) -> [String: Any] {
        guard let objectMessage = objectMessage as? RuntimeStatusObjectMessage else {
            return [:]
        }
        return objectMessage.serialized
    }

    func nosync_onChannelAttached(_ channel: any RealtimeChannel, hasObjects _: Bool) {
        _ = channel
    }

    func nosync_handleObjectProtocolMessage(
        withObjectMessages objectMessages: [any ObjectMessageProtocol],
        channel: any RealtimeChannel
    ) {
        process(objectMessages: objectMessages, channel: channel)
    }

    func nosync_handleObjectSyncProtocolMessage(
        withObjectMessages objectMessages: [any ObjectMessageProtocol],
        protocolMessageChannelSerial _: String?,
        channel: any RealtimeChannel
    ) {
        process(objectMessages: objectMessages, channel: channel)
    }

    func nosync_onConnected(
        withConnectionDetails _: (any ConnectionDetailsProtocol)?,
        channel _: any RealtimeChannel
    ) {
        // No-op.
    }

    private func process(
        objectMessages: [any ObjectMessageProtocol],
        channel: any RealtimeChannel
    ) {
        guard let realtimeChannel = channel as? ARTRealtimeChannel else {
            return
        }

        for objectMessage in objectMessages {
            guard let objectMessage = objectMessage as? RuntimeStatusObjectMessage,
                  let envelope = SessionDetailRuntimeStatusEnvelope.decodeFromLiveObjectMessage(
                      objectMessage.serialized,
                      expectedObjectKey: Config.runtimeStatusObjectKey
                  ) else {
                continue
            }

            dispatcher.publish(channelName: realtimeChannel.name, envelope: envelope)
        }
    }
}

private final class RuntimeStatusLiveObjectsDispatcher {
    typealias Listener = (SessionDetailRuntimeStatusEnvelope) -> Void

    private struct Subscription {
        let id: UUID
        let channelName: String
        let listener: Listener
    }

    private let lock = NSLock()
    private var subscriptions: [UUID: Subscription] = [:]

    @discardableResult
    func register(channelName: String, listener: @escaping Listener) -> UUID {
        let id = UUID()
        lock.lock()
        subscriptions[id] = Subscription(id: id, channelName: channelName, listener: listener)
        lock.unlock()
        return id
    }

    func unregister(_ id: UUID) {
        lock.lock()
        subscriptions.removeValue(forKey: id)
        lock.unlock()
    }

    func publish(channelName: String, envelope: SessionDetailRuntimeStatusEnvelope) {
        lock.lock()
        let listeners = subscriptions.values
            .filter { $0.channelName == channelName }
            .map(\.listener)
        lock.unlock()

        for listener in listeners {
            listener(envelope)
        }
    }
}
#endif
