//
//  SessionControlService.swift
//  unbound-ios
//
//  Manages remote control of Claude Code sessions running on trusted executors.
//  Provides high-level APIs for session lifecycle management and real-time monitoring.
//

import Foundation
import Combine

/// Status of a Claude session
enum SessionStatus: String, Codable {
    case active
    case paused
    case ended
    case error

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .ended: return "Ended"
        case .error: return "Error"
        }
    }

    var isRunning: Bool {
        self == .active || self == .paused
    }
}

/// A Claude Code session that can be remotely controlled
struct ControlledSession: Identifiable, Codable {
    let id: String
    let executorDeviceId: String
    let executorDeviceName: String
    let repositoryName: String
    let branchName: String
    var status: SessionStatus
    let startedAt: Date
    var lastActivityAt: Date
    var currentContent: String
    var isTyping: Bool

    /// Duration since session started
    var duration: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    /// Human-readable duration
    var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}

/// Events emitted by session control
enum SessionControlEvent {
    case sessionDiscovered(ControlledSession)
    case sessionUpdated(ControlledSession)
    case sessionEnded(String)
    case contentUpdate(String, String)  // sessionId, content
    case typingStateChanged(String, Bool)  // sessionId, isTyping
    case controlSuccess(String, RemoteControlAction)
    case controlFailed(String, RemoteControlAction, String)
    case connectionStateChanged(RelayConnectionState)
}

/// Delegate protocol for session control events
protocol SessionControlDelegate: AnyObject {
    func sessionControl(_ service: SessionControlService, didReceive event: SessionControlEvent)
}

/// Service for controlling remote Claude Code sessions
@Observable
final class SessionControlService {
    static let shared = SessionControlService()

    // MARK: - Properties

    /// Currently active sessions
    private(set) var sessions: [ControlledSession] = []

    /// Currently focused session (for single-session view)
    private(set) var focusedSessionId: String?

    /// Connection state to the relay
    var connectionState: RelayConnectionState {
        relayService.connectionState
    }

    /// Whether connected to the relay
    var isConnected: Bool {
        connectionState.isConnected
    }

    private let relayService: RelayConnectionService
    private let deviceTrustService: DeviceTrustService
    private var cancellables = Set<AnyCancellable>()

    weak var delegate: SessionControlDelegate?

    /// Subject for Combine-based event streaming
    let eventSubject = PassthroughSubject<SessionControlEvent, Never>()

    private init(
        relayService: RelayConnectionService = .shared,
        deviceTrustService: DeviceTrustService = .shared
    ) {
        self.relayService = relayService
        self.deviceTrustService = deviceTrustService

        setupRelayEventHandling()
    }

    // MARK: - Connection

    /// Connect to the relay server
    func connect(relayURL: URL, authToken: String) {
        relayService.connect(to: relayURL, authToken: authToken)
    }

    /// Disconnect from the relay
    func disconnect() {
        relayService.disconnect()
        sessions = []
        focusedSessionId = nil
    }

    // MARK: - Session Management

    /// Watch a specific session
    func watchSession(_ sessionId: String) async throws {
        try relayService.joinSession(sessionId)
        focusedSessionId = sessionId
    }

    /// Stop watching the current session
    func stopWatching() throws {
        try relayService.leaveSession()
        focusedSessionId = nil
    }

    /// Get the focused session
    var focusedSession: ControlledSession? {
        guard let focusedSessionId else { return nil }
        return sessions.first { $0.id == focusedSessionId }
    }

    // MARK: - Remote Control

    /// Pause the focused session
    @discardableResult
    func pauseSession() async throws -> Bool {
        guard let sessionId = focusedSessionId else {
            throw SessionControlError.noSessionFocused
        }

        let success = try relayService.pause()
        if success {
            updateSessionStatus(sessionId, status: .paused)
        }
        return success
    }

    /// Resume the focused session
    @discardableResult
    func resumeSession() async throws -> Bool {
        guard let sessionId = focusedSessionId else {
            throw SessionControlError.noSessionFocused
        }

        let success = try relayService.resume()
        if success {
            updateSessionStatus(sessionId, status: .active)
        }
        return success
    }

    /// Stop the focused session
    @discardableResult
    func stopSession() async throws -> Bool {
        guard let sessionId = focusedSessionId else {
            throw SessionControlError.noSessionFocused
        }

        let success = try relayService.stop()
        if success {
            updateSessionStatus(sessionId, status: .ended)
        }
        return success
    }

    /// Send input to the focused session
    @discardableResult
    func sendInput(_ content: String) async throws -> Bool {
        guard focusedSessionId != nil else {
            throw SessionControlError.noSessionFocused
        }

        return try relayService.sendInput(content)
    }

    /// Pause a specific session
    @discardableResult
    func pause(sessionId: String) async throws -> Bool {
        // If not the focused session, join it first
        if focusedSessionId != sessionId {
            try await watchSession(sessionId)
        }
        return try await pauseSession()
    }

    /// Resume a specific session
    @discardableResult
    func resume(sessionId: String) async throws -> Bool {
        if focusedSessionId != sessionId {
            try await watchSession(sessionId)
        }
        return try await resumeSession()
    }

    /// Stop a specific session
    @discardableResult
    func stop(sessionId: String) async throws -> Bool {
        if focusedSessionId != sessionId {
            try await watchSession(sessionId)
        }
        return try await stopSession()
    }

    // MARK: - Content Access

    /// Get the current content for the focused session
    var currentContent: String {
        relayService.currentContent
    }

    /// Get all stream chunks for the focused session
    var streamChunks: [StreamChunk] {
        relayService.streamChunks
    }

    /// Clear the current content buffer
    func clearContent() {
        // This would need to be implemented in RelayConnectionService
    }

    // MARK: - Session Discovery

    /// Add a discovered session
    func addSession(_ session: ControlledSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            emit(.sessionUpdated(session))
        } else {
            sessions.append(session)
            emit(.sessionDiscovered(session))
        }
    }

    /// Remove a session
    func removeSession(_ sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
        if focusedSessionId == sessionId {
            focusedSessionId = nil
        }
        emit(.sessionEnded(sessionId))
    }

    // MARK: - Private Helpers

    private func setupRelayEventHandling() {
        relayService.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleRelayEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleRelayEvent(_ event: RelayEvent) {
        switch event {
        case .connected, .authenticated:
            emit(.connectionStateChanged(connectionState))

        case .disconnected:
            emit(.connectionStateChanged(.disconnected))
            sessions = []
            focusedSessionId = nil

        case .sessionJoined(let sessionId, let participants):
            // Find the executor device to get session info
            if let executor = participants.first(where: { $0.role == .executor }),
               let trustedDevice = deviceTrustService.getTrustedDevice(deviceId: executor.deviceId) {
                let session = ControlledSession(
                    id: sessionId,
                    executorDeviceId: executor.deviceId,
                    executorDeviceName: trustedDevice.name,
                    repositoryName: "Unknown",  // Would come from session metadata
                    branchName: "main",
                    status: .active,
                    startedAt: executor.joinedAt,
                    lastActivityAt: Date(),
                    currentContent: "",
                    isTyping: false
                )
                addSession(session)
            }

        case .sessionLeft(let sessionId):
            if focusedSessionId == sessionId {
                focusedSessionId = nil
            }

        case .streamChunk(let chunk):
            updateSessionActivity(chunk.sessionId)

            if chunk.contentType == .text {
                // Update typing state
                if let index = sessions.firstIndex(where: { $0.id == chunk.sessionId }) {
                    sessions[index].isTyping = !chunk.isComplete
                    sessions[index].lastActivityAt = Date()
                    emit(.typingStateChanged(chunk.sessionId, !chunk.isComplete))
                }

                emit(.contentUpdate(chunk.sessionId, chunk.content))
            }

        case .streamComplete(let sessionId):
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[index].isTyping = false
                emit(.typingStateChanged(sessionId, false))
            }

        case .controlAck(let sessionId, let action, let success):
            if success {
                emit(.controlSuccess(sessionId, action))
            } else {
                emit(.controlFailed(sessionId, action, "Control action failed"))
            }

        case .error(let error):
            emit(.connectionStateChanged(.error(error.localizedDescription)))

        default:
            break
        }
    }

    private func updateSessionStatus(_ sessionId: String, status: SessionStatus) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return
        }
        sessions[index].status = status
        sessions[index].lastActivityAt = Date()
        emit(.sessionUpdated(sessions[index]))
    }

    private func updateSessionActivity(_ sessionId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return
        }
        sessions[index].lastActivityAt = Date()
    }

    private func emit(_ event: SessionControlEvent) {
        delegate?.sessionControl(self, didReceive: event)
        eventSubject.send(event)
    }
}

// MARK: - Errors

enum SessionControlError: Error, LocalizedError {
    case noSessionFocused
    case sessionNotFound
    case notConnected
    case controlFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSessionFocused:
            return "No session is currently focused."
        case .sessionNotFound:
            return "The specified session was not found."
        case .notConnected:
            return "Not connected to the relay server."
        case .controlFailed(let reason):
            return "Control action failed: \(reason)"
        }
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

private struct SessionControlServiceKey: EnvironmentKey {
    static let defaultValue = SessionControlService.shared
}

extension EnvironmentValues {
    var sessionControlService: SessionControlService {
        get { self[SessionControlServiceKey.self] }
        set { self[SessionControlServiceKey.self] = newValue }
    }
}
