//
//  OutputBroadcastService.swift
//  unbound-macos
//
//  Re-encrypts Claude output for each viewer in a multi-device session.
//  Handles fan-out of encrypted messages to trust root and web viewers.
//

import Foundation
import CryptoKit
import Combine

/// Content type for stream chunks
enum StreamContentType: String, Codable {
    case text
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case system
    case error
}

/// A chunk of Claude output to broadcast
struct OutputChunk {
    let content: String
    let contentType: StreamContentType
    let sequenceNumber: Int
    let isComplete: Bool
    let timestamp: Date

    init(
        content: String,
        contentType: StreamContentType = .text,
        sequenceNumber: Int,
        isComplete: Bool = false
    ) {
        self.content = content
        self.contentType = contentType
        self.sequenceNumber = sequenceNumber
        self.isComplete = isComplete
        self.timestamp = Date()
    }
}

/// Encrypted message for a specific recipient
struct EncryptedOutputMessage {
    let recipientId: String
    let nonce: Data
    let ciphertext: Data
    let sessionId: String
    let sequenceNumber: Int
}

/// Service for broadcasting encrypted output to multiple viewers
@Observable
final class OutputBroadcastService {
    static let shared = OutputBroadcastService()

    private let relayClientService: RelayClientService
    private let deviceIdentityService: DeviceIdentityService
    private let cryptoService: CryptoService

    /// Current session ID
    private(set) var currentSessionId: String?

    /// Sequence counter for output chunks
    private(set) var sequenceNumber: Int = 0

    /// Whether broadcasting is active
    private(set) var isBroadcasting: Bool = false

    /// Buffer for accumulated text chunks
    private var textBuffer = ""
    private var bufferFlushTimer: Timer?

    /// Session keys for each viewer (derived per-session)
    private var viewerSessionKeys: [String: SymmetricKey] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init(
        relayClientService: RelayClientService = .shared,
        deviceIdentityService: DeviceIdentityService = .shared,
        cryptoService: CryptoService = .shared
    ) {
        self.relayClientService = relayClientService
        self.deviceIdentityService = deviceIdentityService
        self.cryptoService = cryptoService

        // Listen for viewer changes
        relayClientService.eventSubject
            .sink { [weak self] event in
                self?.handleRelayEvent(event)
            }
            .store(in: &cancellables)
    }

    // MARK: - Session Management

    /// Start a new broadcast session
    func startSession(_ sessionId: String) throws {
        guard relayClientService.connectionState.isConnected else {
            throw OutputBroadcastError.notConnected
        }

        currentSessionId = sessionId
        sequenceNumber = 0
        textBuffer = ""
        viewerSessionKeys = [:]
        isBroadcasting = true

        // Derive session key for trust root
        if let trustRoot = deviceIdentityService.trustRoot {
            let key = try deviceIdentityService.deriveSessionKey(
                with: trustRoot.deviceId,
                sessionId: sessionId
            )
            viewerSessionKeys[trustRoot.deviceId] = key
        }

        try relayClientService.startSession(sessionId)
    }

    /// End the current broadcast session
    func endSession() throws {
        flushBuffer()

        isBroadcasting = false
        currentSessionId = nil
        viewerSessionKeys = [:]

        try relayClientService.endSession()
    }

    // MARK: - Broadcasting

    /// Broadcast a text chunk to all viewers
    func broadcastText(_ text: String, isComplete: Bool = false) {
        guard isBroadcasting else { return }

        textBuffer += text

        if isComplete {
            flushBuffer()
        } else {
            // Debounce: flush buffer after short delay
            bufferFlushTimer?.invalidate()
            bufferFlushTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                self?.flushBuffer()
            }
        }
    }

    /// Broadcast a tool use event
    func broadcastToolUse(
        toolId: String,
        toolName: String,
        input: String,
        status: String = "running"
    ) {
        guard isBroadcasting else { return }

        let payload: [String: Any] = [
            "id": toolId,
            "name": toolName,
            "input": input,
            "status": status
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let content = String(data: jsonData, encoding: .utf8) ?? "{}"

            let chunk = OutputChunk(
                content: content,
                contentType: .toolUse,
                sequenceNumber: nextSequenceNumber(),
                isComplete: false
            )
            broadcastChunk(chunk)
        } catch {
            print("Failed to serialize tool use: \(error)")
        }
    }

    /// Broadcast a tool result
    func broadcastToolResult(
        toolId: String,
        output: String,
        duration: TimeInterval? = nil
    ) {
        guard isBroadcasting else { return }

        var payload: [String: Any] = [
            "toolId": toolId,
            "output": output
        ]

        if let duration {
            payload["duration"] = duration
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            let content = String(data: jsonData, encoding: .utf8) ?? "{}"

            let chunk = OutputChunk(
                content: content,
                contentType: .toolResult,
                sequenceNumber: nextSequenceNumber(),
                isComplete: true
            )
            broadcastChunk(chunk)
        } catch {
            print("Failed to serialize tool result: \(error)")
        }
    }

    /// Broadcast a system message
    func broadcastSystemMessage(_ message: String) {
        guard isBroadcasting else { return }

        let chunk = OutputChunk(
            content: message,
            contentType: .system,
            sequenceNumber: nextSequenceNumber(),
            isComplete: true
        )
        broadcastChunk(chunk)
    }

    /// Broadcast an error
    func broadcastError(_ error: String) {
        guard isBroadcasting else { return }

        let chunk = OutputChunk(
            content: error,
            contentType: .error,
            sequenceNumber: nextSequenceNumber(),
            isComplete: true
        )
        broadcastChunk(chunk)
    }

    /// Signal that the stream is complete
    func broadcastComplete() {
        flushBuffer()

        do {
            try relayClientService.broadcastStreamComplete()
        } catch {
            print("Failed to broadcast stream complete: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func flushBuffer() {
        bufferFlushTimer?.invalidate()
        bufferFlushTimer = nil

        guard !textBuffer.isEmpty else { return }

        let chunk = OutputChunk(
            content: textBuffer,
            contentType: .text,
            sequenceNumber: nextSequenceNumber(),
            isComplete: false
        )
        broadcastChunk(chunk)
        textBuffer = ""
    }

    private func broadcastChunk(_ chunk: OutputChunk) {
        do {
            try relayClientService.broadcastStreamChunk(
                content: chunk.content,
                contentType: chunk.contentType.rawValue,
                sequenceNumber: chunk.sequenceNumber,
                isComplete: chunk.isComplete
            )
        } catch {
            print("Failed to broadcast chunk: \(error)")
        }
    }

    private func nextSequenceNumber() -> Int {
        sequenceNumber += 1
        return sequenceNumber
    }

    /// Encrypt a message for a specific viewer
    private func encryptForViewer(
        _ content: String,
        viewerId: String,
        sessionId: String
    ) throws -> EncryptedOutputMessage {
        // Get or derive session key for this viewer
        let sessionKey = try getOrDeriveSessionKey(for: viewerId, sessionId: sessionId)

        // Encrypt the content
        let encrypted = try cryptoService.encrypt(content, using: sessionKey)

        return EncryptedOutputMessage(
            recipientId: viewerId,
            nonce: encrypted.nonce,
            ciphertext: encrypted.ciphertext,
            sessionId: sessionId,
            sequenceNumber: sequenceNumber
        )
    }

    private func getOrDeriveSessionKey(
        for viewerId: String,
        sessionId: String
    ) throws -> SymmetricKey {
        if let existingKey = viewerSessionKeys[viewerId] {
            return existingKey
        }

        // Check if this is a trusted device
        if deviceIdentityService.isTrusted(deviceId: viewerId) {
            let key = try deviceIdentityService.deriveSessionKey(
                with: viewerId,
                sessionId: sessionId
            )
            viewerSessionKeys[viewerId] = key
            return key
        }

        // For web viewers, we'd need their public key from the relay
        // For now, throw an error - web session keys should be set up separately
        throw OutputBroadcastError.unknownViewer(viewerId)
    }

    /// Add a session key for a web viewer
    func addViewerSessionKey(_ viewerId: String, key: SymmetricKey) {
        viewerSessionKeys[viewerId] = key
    }

    /// Remove a viewer's session key
    func removeViewerSessionKey(_ viewerId: String) {
        viewerSessionKeys.removeValue(forKey: viewerId)
    }

    private func handleRelayEvent(_ event: RelayClientEvent) {
        switch event {
        case .viewerJoined(let sessionId, let viewerId):
            // New viewer joined - they should have received their session key
            // during their authorization flow
            print("Viewer joined: \(viewerId) for session \(sessionId)")

        case .viewerLeft(_, let viewerId):
            removeViewerSessionKey(viewerId)

        default:
            break
        }
    }
}

// MARK: - Errors

enum OutputBroadcastError: Error, LocalizedError {
    case notConnected
    case noActiveSession
    case unknownViewer(String)
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to relay server."
        case .noActiveSession:
            return "No active broadcast session."
        case .unknownViewer(let viewerId):
            return "Unknown viewer: \(viewerId). No session key available."
        case .encryptionFailed:
            return "Failed to encrypt message for viewer."
        }
    }
}

// MARK: - ClaudeService Integration Extension

extension ClaudeService {
    /// Start broadcasting output for the current session
    func startBroadcasting(sessionId: String) {
        do {
            try OutputBroadcastService.shared.startSession(sessionId)
        } catch {
            print("Failed to start broadcasting: \(error)")
        }
    }

    /// Stop broadcasting
    func stopBroadcasting() {
        do {
            try OutputBroadcastService.shared.endSession()
        } catch {
            print("Failed to stop broadcasting: \(error)")
        }
    }

    /// Broadcast a text chunk from Claude output
    func broadcastOutput(_ text: String, isComplete: Bool = false) {
        OutputBroadcastService.shared.broadcastText(text, isComplete: isComplete)
    }

    /// Broadcast tool use
    func broadcastToolUse(id: String, name: String, input: String) {
        OutputBroadcastService.shared.broadcastToolUse(
            toolId: id,
            toolName: name,
            input: input
        )
    }

    /// Broadcast tool result
    func broadcastToolResult(id: String, output: String, duration: TimeInterval?) {
        OutputBroadcastService.shared.broadcastToolResult(
            toolId: id,
            output: output,
            duration: duration
        )
    }
}
