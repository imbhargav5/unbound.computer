//
//  RelayConnectionService.swift
//  unbound-ios
//
//  WebSocket client for connecting to the relay server.
//  Handles real-time session streaming and encrypted message routing.
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
    case authenticate = "AUTH"
    case authenticated = "AUTH_RESULT"
    case error = "ERROR"

    // Sessions (uppercase to match server protocol)
    case joinSession = "JOIN_SESSION"
    case leaveSession = "LEAVE_SESSION"
    case sessionJoined = "SUBSCRIBED"
    case sessionLeft = "UNSUBSCRIBED"

    // Streaming
    case streamChunk = "stream_chunk"
    case streamComplete = "stream_complete"

    // Remote control
    case remoteControl = "remote_control"
    case controlAck = "control_ack"

    // Presence
    case presence
    case heartbeat = "HEARTBEAT"
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

/// Stream chunk from a Claude session
struct StreamChunk: Codable {
    let sessionId: String
    let sequenceNumber: Int
    let contentType: StreamContentType
    let content: String
    let isComplete: Bool
    let timestamp: Date

    enum StreamContentType: String, Codable {
        case text
        case toolUse = "tool_use"
        case toolResult = "tool_result"
        case system
        case error
    }
}

/// Session participant info
struct SessionParticipant: Codable, Identifiable {
    let deviceId: String
    let role: RelayClientRole
    let permission: String?
    let joinedAt: Date

    var id: String { deviceId }
}

/// Events emitted by the relay connection
enum RelayEvent {
    case connected
    case disconnected(Error?)
    case authenticated
    case authenticationFailed(String)
    case sessionJoined(String, [SessionParticipant])
    case sessionLeft(String)
    case streamChunk(StreamChunk)
    case streamComplete(String)
    case controlAck(String, RemoteControlAction, Bool)
    case participantJoined(String, SessionParticipant)
    case participantLeft(String, String)
    case error(Error)
}

/// Delegate protocol for relay events
protocol RelayConnectionDelegate: AnyObject {
    func relayConnection(_ connection: RelayConnectionService, didReceive event: RelayEvent)
}

/// Service for managing WebSocket connection to the relay
@Observable
final class RelayConnectionService {
    static let shared = RelayConnectionService()

    // MARK: - Properties

    private(set) var connectionState: RelayConnectionState = .disconnected
    private(set) var currentSessionId: String?
    private(set) var participants: [SessionParticipant] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private let deviceTrustService: DeviceTrustService
    private let cryptoService: CryptoService

    weak var delegate: RelayConnectionDelegate?

    /// Subject for Combine-based event streaming
    let eventSubject = PassthroughSubject<RelayEvent, Never>()

    /// Current stream chunks for the active session
    private(set) var streamChunks: [StreamChunk] = []

    /// Accumulated content from stream chunks
    var currentContent: String {
        streamChunks
            .filter { $0.contentType == .text }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .map(\.content)
            .joined()
    }

    private init(
        deviceTrustService: DeviceTrustService = .shared,
        cryptoService: CryptoService = .shared
    ) {
        self.deviceTrustService = deviceTrustService
        self.cryptoService = cryptoService
        self.urlSession = URLSession(configuration: .default)
    }

    // MARK: - Connection

    /// Connect to the relay server
    func connect(to relayURL: URL, authToken: String) {
        guard connectionState == .disconnected || connectionState != .connecting else {
            return
        }

        connectionState = .connecting

        var request = URLRequest(url: relayURL)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("ios", forHTTPHeaderField: "X-Device-Type")

        if let deviceId = deviceTrustService.deviceId {
            request.setValue(deviceId.uuidString, forHTTPHeaderField: "X-Device-ID")
        }

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        // Start receiving messages
        startReceiving()

        // Authenticate after connection
        connectionState = .authenticating
        authenticate(token: authToken)
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
        participants = []
        streamChunks = []

        emit(.disconnected(nil))
    }

    // MARK: - Authentication

    private func authenticate(token: String) {
        guard let deviceId = deviceTrustService.deviceId else {
            connectionState = .error("Device not initialized")
            emit(.authenticationFailed("Device not initialized"))
            return
        }

        let payload: [String: Any] = [
            "token": token,
            "deviceId": deviceId.uuidString,
            "deviceName": deviceTrustService.deviceName,
            "role": RelayClientRole.controller.rawValue
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

    /// Join a Claude session to receive real-time updates
    func joinSession(_ sessionId: String) throws {
        guard connectionState.isConnected else {
            throw RelayConnectionError.notConnected
        }

        let payload: [String: Any] = [
            "sessionId": sessionId,
            "role": RelayClientRole.controller.rawValue
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadString = String(data: payloadData, encoding: .utf8)

        let message = RelayMessage(type: .joinSession, sessionId: sessionId, payload: payloadString)
        try send(message)
    }

    /// Leave the current session
    func leaveSession() throws {
        guard let sessionId = currentSessionId else { return }

        let message = RelayMessage(type: .leaveSession, sessionId: sessionId)
        try send(message)

        currentSessionId = nil
        participants = []
        streamChunks = []
    }

    // MARK: - Remote Control

    /// Send a remote control command to the executor
    func sendRemoteControl(
        action: RemoteControlAction,
        content: String? = nil
    ) throws -> Bool {
        guard connectionState.isConnected, let sessionId = currentSessionId else {
            return false
        }

        var payload: [String: Any] = [
            "action": action.rawValue,
            "sessionId": sessionId,
            "requesterId": deviceTrustService.deviceId?.uuidString ?? ""
        ]

        if let content {
            payload["content"] = content
        }

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadString = String(data: payloadData, encoding: .utf8)

        let message = RelayMessage(type: .remoteControl, sessionId: sessionId, payload: payloadString)
        try send(message)

        return true
    }

    /// Pause the current Claude session
    func pause() throws -> Bool {
        try sendRemoteControl(action: .pause)
    }

    /// Resume the current Claude session
    func resume() throws -> Bool {
        try sendRemoteControl(action: .resume)
    }

    /// Stop the current Claude session
    func stop() throws -> Bool {
        try sendRemoteControl(action: .stop)
    }

    /// Send input to the current Claude session
    func sendInput(_ content: String) throws -> Bool {
        try sendRemoteControl(action: .input, content: content)
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
            currentSessionId = message.sessionId
            streamChunks = []

            // Parse participants from payload
            if let payloadData = message.payload?.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
               let participantsData = json["participants"] as? [[String: Any]] {
                participants = participantsData.compactMap { parseParticipant($0) }
            }

            emit(.sessionJoined(message.sessionId ?? "", participants))

        case .sessionLeft:
            emit(.sessionLeft(message.sessionId ?? ""))
            if message.sessionId == currentSessionId {
                currentSessionId = nil
                participants = []
                streamChunks = []
            }

        case .streamChunk:
            if let chunk = parseStreamChunk(from: message.payload) {
                streamChunks.append(chunk)
                emit(.streamChunk(chunk))
            }

        case .streamComplete:
            emit(.streamComplete(message.sessionId ?? ""))

        case .controlAck:
            if let payload = message.payload?.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
               let actionStr = json["action"] as? String,
               let action = RemoteControlAction(rawValue: actionStr),
               let success = json["success"] as? Bool {
                emit(.controlAck(message.sessionId ?? "", action, success))
            }

        case .presence:
            if let payload = message.payload?.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                if let joined = json["joined"] as? [String: Any],
                   let participant = parseParticipant(joined) {
                    if !participants.contains(where: { $0.deviceId == participant.deviceId }) {
                        participants.append(participant)
                    }
                    emit(.participantJoined(message.sessionId ?? "", participant))
                }
                if let leftDeviceId = json["left"] as? String {
                    participants.removeAll { $0.deviceId == leftDeviceId }
                    emit(.participantLeft(message.sessionId ?? "", leftDeviceId))
                }
            }

        default:
            break
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
            // Reconnection logic would go here with stored credentials
        }
    }

    // MARK: - Helpers

    private func emit(_ event: RelayEvent) {
        delegate?.relayConnection(self, didReceive: event)
        eventSubject.send(event)
    }

    private func parseStreamChunk(from payload: String?) -> StreamChunk? {
        guard let data = payload?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StreamChunk.self, from: data)
    }

    private func parseParticipant(_ dict: [String: Any]) -> SessionParticipant? {
        guard let deviceId = dict["deviceId"] as? String,
              let roleStr = dict["role"] as? String,
              let role = RelayClientRole(rawValue: roleStr) else {
            return nil
        }

        return SessionParticipant(
            deviceId: deviceId,
            role: role,
            permission: dict["permission"] as? String,
            joinedAt: (dict["joinedAt"] as? Date) ?? Date()
        )
    }
}

// MARK: - Errors

enum RelayConnectionError: Error, LocalizedError {
    case notConnected
    case sessionNotJoined
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to relay server."
        case .sessionNotJoined:
            return "Not currently in a session."
        case .sendFailed:
            return "Failed to send message."
        }
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

private struct RelayConnectionServiceKey: EnvironmentKey {
    static let defaultValue = RelayConnectionService.shared
}

extension EnvironmentValues {
    var relayService: RelayConnectionService {
        get { self[RelayConnectionServiceKey.self] }
        set { self[RelayConnectionServiceKey.self] = newValue }
    }
}
