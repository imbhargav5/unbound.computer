//
//  RelayClientService.swift
//  unbound-macos
//
//  WebSocket client for connecting to the relay server as a trusted executor.
//  Receives commands from iOS trust root and broadcasts output to viewers.
//

import Foundation
import CryptoKit
import Combine

/// Connection state for the relay
enum RelayConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(String)

    var isConnected: Bool {
        self == .connected
    }
}

/// Role of this client in the relay
enum RelayClientRole: String, Codable {
    case controller  // iOS device (trust root)
    case executor    // Mac device (trusted executor)
    case viewer      // Web viewer (temporary)
}

/// Message types for the relay protocol
enum RelayMessageType: String, Codable {
    // Connection
    case authenticate
    case authenticated
    case error

    // Roles
    case registerRole = "register_role"
    case roleRegistered = "role_registered"

    // Sessions
    case joinSession = "join_session"
    case leaveSession = "leave_session"
    case sessionJoined = "session_joined"
    case sessionLeft = "session_left"

    // Streaming
    case streamChunk = "stream_chunk"
    case streamComplete = "stream_complete"

    // Remote control
    case remoteControl = "remote_control"
    case controlAck = "control_ack"

    // Presence
    case presence
    case heartbeat
}

/// Remote control actions
enum RemoteControlAction: String, Codable {
    case pause
    case resume
    case stop
    case input
}

/// A message sent to/from the relay
struct RelayMessage: Codable {
    let type: RelayMessageType
    let sessionId: String?
    let payload: String?  // JSON-encoded payload
    let timestamp: Date

    init(type: RelayMessageType, sessionId: String? = nil, payload: String? = nil) {
        self.type = type
        self.sessionId = sessionId
        self.payload = payload
        self.timestamp = Date()
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> RelayMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RelayMessage.self, from: data)
    }
}

/// Remote control command received from trust root
struct RemoteControlCommand {
    let action: RemoteControlAction
    let sessionId: String
    let requesterId: String
    let content: String?
}

/// Events emitted by the relay client
enum RelayClientEvent {
    case connected
    case disconnected(Error?)
    case authenticated
    case authenticationFailed(String)
    case remoteControl(RemoteControlCommand)
    case viewerJoined(String, String)  // sessionId, viewerId
    case viewerLeft(String, String)
    case error(Error)
}

/// Delegate protocol for relay client events
protocol RelayClientDelegate: AnyObject {
    func relayClient(_ client: RelayClientService, didReceive event: RelayClientEvent)
    func relayClient(_ client: RelayClientService, shouldHandle command: RemoteControlCommand) -> Bool
}

/// Service for managing WebSocket connection to the relay as executor
@Observable
final class RelayClientService {
    static let shared = RelayClientService()

    // MARK: - Properties

    private(set) var connectionState: RelayConnectionState = .disconnected
    private(set) var currentSessionId: String?
    private(set) var viewers: [String: String] = [:]  // viewerId -> permission

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private let deviceIdentityService: DeviceIdentityService
    private let cryptoService: CryptoService

    weak var delegate: RelayClientDelegate?

    /// Subject for Combine-based event streaming
    let eventSubject = PassthroughSubject<RelayClientEvent, Never>()

    /// Handlers for remote control commands
    var onPauseRemote: (() -> Void)?
    var onResumeRemote: (() -> Void)?
    var onStopRemote: (() -> Void)?
    var onInputRemote: ((String) -> Void)?

    private var relayURL: URL?
    private var authToken: String?

    private init(
        deviceIdentityService: DeviceIdentityService = .shared,
        cryptoService: CryptoService = .shared
    ) {
        self.deviceIdentityService = deviceIdentityService
        self.cryptoService = cryptoService
        self.urlSession = URLSession(configuration: .default)
    }

    // MARK: - Connection

    /// Connect to the relay server
    func connect(to relayURL: URL, authToken: String) {
        guard connectionState == .disconnected else { return }

        self.relayURL = relayURL
        self.authToken = authToken

        connectionState = .connecting

        var request = URLRequest(url: relayURL)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("macos", forHTTPHeaderField: "X-Device-Type")

        if let deviceId = deviceIdentityService.deviceId {
            request.setValue(deviceId.uuidString, forHTTPHeaderField: "X-Device-ID")
        }

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        // Start receiving messages
        startReceiving()

        // Authenticate
        connectionState = .authenticating
        authenticate()
    }

    /// Disconnect from the relay
    func disconnect() {
        stopHeartbeat()
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        connectionState = .disconnected
        currentSessionId = nil
        viewers = [:]

        emit(.disconnected(nil))
    }

    /// Reconnect to the relay
    func reconnect() {
        guard let url = relayURL, let token = authToken else { return }
        disconnect()
        connect(to: url, authToken: token)
    }

    // MARK: - Authentication

    private func authenticate() {
        guard let deviceId = deviceIdentityService.deviceId else {
            connectionState = .error("Device not initialized")
            emit(.authenticationFailed("Device not initialized"))
            return
        }

        let payload: [String: Any] = [
            "deviceId": deviceId.uuidString,
            "deviceName": deviceIdentityService.deviceName,
            "role": RelayClientRole.executor.rawValue
        ]

        do {
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let payloadString = String(data: payloadData, encoding: .utf8)

            let message = RelayMessage(type: .authenticate, payload: payloadString)
            try send(message)
        } catch {
            connectionState = .error("Authentication failed: \(error.localizedDescription)")
            emit(.authenticationFailed(error.localizedDescription))
        }
    }

    // MARK: - Session Management

    /// Start a new session and register with the relay
    func startSession(_ sessionId: String) throws {
        guard connectionState.isConnected else {
            throw RelayClientError.notConnected
        }

        currentSessionId = sessionId

        let payload: [String: Any] = [
            "sessionId": sessionId,
            "role": RelayClientRole.executor.rawValue
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadString = String(data: payloadData, encoding: .utf8)

        let message = RelayMessage(type: .joinSession, sessionId: sessionId, payload: payloadString)
        try send(message)
    }

    /// End the current session
    func endSession() throws {
        guard let sessionId = currentSessionId else { return }

        let message = RelayMessage(type: .leaveSession, sessionId: sessionId)
        try send(message)

        currentSessionId = nil
        viewers = [:]
    }

    // MARK: - Output Broadcasting

    /// Broadcast a stream chunk to all viewers
    func broadcastStreamChunk(
        content: String,
        contentType: String,
        sequenceNumber: Int,
        isComplete: Bool
    ) throws {
        guard connectionState.isConnected, let sessionId = currentSessionId else {
            throw RelayClientError.notConnected
        }

        let chunkPayload: [String: Any] = [
            "sessionId": sessionId,
            "sequenceNumber": sequenceNumber,
            "contentType": contentType,
            "content": content,
            "isComplete": isComplete,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: chunkPayload)
        let payloadString = String(data: payloadData, encoding: .utf8)

        let message = RelayMessage(type: .streamChunk, sessionId: sessionId, payload: payloadString)
        try send(message)
    }

    /// Signal that the stream is complete
    func broadcastStreamComplete() throws {
        guard connectionState.isConnected, let sessionId = currentSessionId else {
            throw RelayClientError.notConnected
        }

        let message = RelayMessage(type: .streamComplete, sessionId: sessionId)
        try send(message)
    }

    // MARK: - Control Acknowledgment

    /// Send acknowledgment for a control command
    func sendControlAck(action: RemoteControlAction, success: Bool, message: String? = nil) throws {
        guard connectionState.isConnected, let sessionId = currentSessionId else {
            throw RelayClientError.notConnected
        }

        var payload: [String: Any] = [
            "action": action.rawValue,
            "success": success
        ]

        if let message {
            payload["message"] = message
        }

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadString = String(data: payloadData, encoding: .utf8)

        let msg = RelayMessage(type: .controlAck, sessionId: sessionId, payload: payloadString)
        try send(msg)
    }

    // MARK: - Message Sending

    private func send(_ message: RelayMessage) throws {
        let data = try message.encode()
        let wsMessage = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error {
                self?.handleError(error)
            }
        }
    }

    // MARK: - Message Receiving

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let webSocketTask else { break }

                do {
                    let message = try await webSocketTask.receive()
                    await MainActor.run {
                        self.handleMessage(message)
                    }
                } catch {
                    await MainActor.run {
                        self.handleError(error)
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            processMessage(data)
        case .string(let string):
            if let data = string.data(using: .utf8) {
                processMessage(data)
            }
        @unknown default:
            break
        }
    }

    private func processMessage(_ data: Data) {
        do {
            let message = try RelayMessage.decode(from: data)
            handleRelayMessage(message)
        } catch {
            emit(.error(error))
        }
    }

    private func handleRelayMessage(_ message: RelayMessage) {
        switch message.type {
        case .authenticated:
            connectionState = .connected
            startHeartbeat()
            emit(.authenticated)

        case .error:
            if let payload = message.payload {
                connectionState = .error(payload)
                emit(.authenticationFailed(payload))
            }

        case .sessionJoined:
            // Session registration confirmed
            break

        case .remoteControl:
            handleRemoteControl(message)

        case .presence:
            handlePresence(message)

        default:
            break
        }
    }

    private func handleRemoteControl(_ message: RelayMessage) {
        guard let payload = message.payload?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let actionStr = json["action"] as? String,
              let action = RemoteControlAction(rawValue: actionStr),
              let sessionId = message.sessionId ?? json["sessionId"] as? String else {
            return
        }

        let command = RemoteControlCommand(
            action: action,
            sessionId: sessionId,
            requesterId: json["requesterId"] as? String ?? "",
            content: json["content"] as? String
        )

        // Check with delegate if we should handle this command
        if let delegate, !delegate.relayClient(self, shouldHandle: command) {
            return
        }

        emit(.remoteControl(command))

        // Execute the command
        switch action {
        case .pause:
            onPauseRemote?()
            try? sendControlAck(action: .pause, success: true)

        case .resume:
            onResumeRemote?()
            try? sendControlAck(action: .resume, success: true)

        case .stop:
            onStopRemote?()
            try? sendControlAck(action: .stop, success: true)

        case .input:
            if let content = command.content {
                onInputRemote?(content)
                try? sendControlAck(action: .input, success: true)
            }
        }
    }

    private func handlePresence(_ message: RelayMessage) {
        guard let payload = message.payload?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sessionId = message.sessionId else {
            return
        }

        if let joined = json["joined"] as? [String: Any],
           let viewerId = joined["deviceId"] as? String {
            let permission = joined["permission"] as? String ?? "view_only"
            viewers[viewerId] = permission
            emit(.viewerJoined(sessionId, viewerId))
        }

        if let leftId = json["left"] as? String {
            viewers.removeValue(forKey: leftId)
            emit(.viewerLeft(sessionId, leftId))
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))

                guard let self, connectionState.isConnected else { break }

                let message = RelayMessage(type: .heartbeat)
                try? send(message)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        connectionState = .error(error.localizedDescription)
        emit(.error(error))

        // Attempt reconnection for transient errors
        if isTransientError(error) {
            scheduleReconnect()
        }
    }

    private func isTransientError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut
        ].contains(nsError.code)
    }

    private func scheduleReconnect() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            reconnect()
        }
    }

    // MARK: - Helpers

    private func emit(_ event: RelayClientEvent) {
        delegate?.relayClient(self, didReceive: event)
        eventSubject.send(event)
    }
}

// MARK: - Errors

enum RelayClientError: Error, LocalizedError {
    case notConnected
    case sessionNotStarted
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to relay server."
        case .sessionNotStarted:
            return "No session has been started."
        case .sendFailed:
            return "Failed to send message."
        }
    }
}
