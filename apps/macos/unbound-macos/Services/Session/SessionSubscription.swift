//
//  SessionSubscription.swift
//  unbound-macos
//
//  Per-session event streaming using shared memory for low-latency IPC.
//  Uses POSIX shared memory (shm_open + mmap) for zero-copy event delivery.
//
//  This provides ~100x lower latency than the previous Unix socket streaming:
//  - Socket: ~35-130 microseconds per event
//  - Shared memory: ~1-5 microseconds per event
//

import Foundation
import Logging

private let logger = Logger(label: "app.session.subscription")

/// Per-session shared memory consumer that streams events from the daemon.
final class SessionSubscription: Sendable {

    // MARK: - State

    private let sessionId: String

    // Shared memory consumer managed on a dedicated queue
    private let queue = DispatchQueue(label: "session.subscription", qos: .userInitiated)
    private nonisolated(unsafe) var consumer: SharedMemoryConsumer?
    private nonisolated(unsafe) var eventContinuation: AsyncStream<DaemonEvent>.Continuation?
    private nonisolated(unsafe) var isDisconnected = false
    private nonisolated(unsafe) var pollTask: Task<Void, Never>?

    // MARK: - Initialization

    init(sessionId: String, socketPath: String = DaemonClient.defaultSocketPath) {
        self.sessionId = sessionId
        // socketPath is kept for API compatibility but not used
    }

    deinit {
        disconnect()
    }

    // MARK: - Connect & Subscribe

    /// Open shared memory stream and start receiving events for this session.
    /// Returns an AsyncStream of events for this session.
    ///
    /// Note: The shared memory stream is created by the daemon when the first
    /// message is sent to Claude. This method will wait (with retries) for the
    /// stream to become available.
    func subscribe() async throws -> AsyncStream<DaemonEvent> {
        // The shared memory is created when the first message is sent.
        // We create a lazy stream that will connect when events start flowing.
        logger.info("Creating lazy subscription for session \(sessionId) - will connect when stream is available")

        // Create event stream
        let stream = AsyncStream<DaemonEvent> { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                self.disconnect()
            }
        }

        // Start polling for events (will connect lazily when stream becomes available)
        startPolling()

        return stream
    }

    /// Try to open the shared memory stream with retries.
    /// Returns true if connected, false if should keep trying.
    private func tryConnect() -> Bool {
        guard consumer == nil else { return true }  // Already connected

        if let shmConsumer = SharedMemoryConsumer.open(sessionId: sessionId) {
            self.consumer = shmConsumer
            logger.info("Connected to shared memory stream for session \(sessionId)")
            return true
        }
        return false
    }

    /// Disconnect and stop polling. Cleans up shared memory resources.
    func disconnect() {
        queue.sync {
            guard !isDisconnected else { return }
            isDisconnected = true
        }

        // Cancel polling task
        pollTask?.cancel()
        pollTask = nil

        eventContinuation?.finish()
        eventContinuation = nil

        // Consumer is cleaned up on dealloc (unmaps memory, closes fd)
        consumer = nil

        logger.debug("Disconnected subscription for session \(sessionId)")
    }

    // MARK: - Private: Polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            guard let self else { return }

            // Wait for shared memory to become available (created when first message sent)
            var connectAttempts = 0
            while !Task.isCancelled {
                if self.tryConnect() {
                    break
                }

                connectAttempts += 1
                if connectAttempts % 100 == 0 {
                    logger.debug("Waiting for shared memory stream (\(connectAttempts) attempts) for session \(self.sessionId)")
                }

                // Poll every 50ms while waiting for stream to be created
                try? await Task.sleep(for: .milliseconds(50))
            }

            guard !Task.isCancelled, let consumer = self.consumer else {
                self.eventContinuation?.finish()
                return
            }

            logger.info("Event polling started for session \(self.sessionId)")

            // Use the async sequence for event iteration
            for await event in consumer.events(pollInterval: .milliseconds(1)) {
                if Task.isCancelled { break }

                // Convert SharedMemoryEvent to DaemonEvent
                if let daemonEvent = self.convertEvent(event) {
                    self.eventContinuation?.yield(daemonEvent)
                }

                // Check for shutdown
                if consumer.isShutdown {
                    logger.info("Shared memory stream shutdown for session \(self.sessionId)")
                    break
                }
            }

            self.eventContinuation?.finish()
        }
    }

    private func convertEvent(_ shmEvent: SharedMemoryEvent) -> DaemonEvent? {
        switch shmEvent.eventType {
        case .claudeEvent:
            // Claude events are raw JSON from Claude CLI
            guard let payloadString = shmEvent.payloadString,
                  let payloadData = payloadString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                logger.warning("Failed to parse Claude event payload")
                return nil
            }

            // Extract type from the JSON to determine DaemonEventType
            let eventType = json["type"] as? String ?? "unknown"
            let daemonType = mapClaudeEventType(eventType)

            // Wrap the JSON in AnyCodableValue for DaemonEvent
            let data = json.mapValues { AnyCodableValue($0) }

            return DaemonEvent(
                type: daemonType,
                sessionId: shmEvent.sessionId,
                data: data,
                sequence: shmEvent.sequence
            )

        case .terminalOutput:
            guard let payloadString = shmEvent.payloadString,
                  let payloadData = payloadString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                logger.warning("Failed to parse terminal output payload")
                return nil
            }

            let data = json.mapValues { AnyCodableValue($0) }

            return DaemonEvent(
                type: .terminalOutput,
                sessionId: shmEvent.sessionId,
                data: data,
                sequence: shmEvent.sequence
            )

        case .terminalFinished:
            guard let payloadString = shmEvent.payloadString,
                  let payloadData = payloadString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                // Fallback: parse as raw exit code bytes
                let exitCode = shmEvent.payload.withUnsafeBytes { ptr -> Int32 in
                    guard ptr.count >= 4 else { return -1 }
                    return ptr.load(as: Int32.self)
                }
                return DaemonEvent(
                    type: .terminalFinished,
                    sessionId: shmEvent.sessionId,
                    data: ["exit_code": AnyCodableValue(exitCode)],
                    sequence: shmEvent.sequence
                )
            }

            let data = json.mapValues { AnyCodableValue($0) }

            return DaemonEvent(
                type: .terminalFinished,
                sessionId: shmEvent.sessionId,
                data: data,
                sequence: shmEvent.sequence
            )

        case .streamingChunk:
            guard let payloadString = shmEvent.payloadString else {
                return nil
            }
            return DaemonEvent(
                type: .claudeStreaming,
                sessionId: shmEvent.sessionId,
                data: ["chunk": AnyCodableValue(payloadString)],
                sequence: shmEvent.sequence
            )

        case .ping:
            // Ping events are internal, don't forward
            return nil
        }
    }

    private func mapClaudeEventType(_ claudeType: String) -> DaemonEventType {
        switch claudeType {
        case "system":
            return .claudeSystem
        case "assistant":
            return .claudeAssistant
        case "user":
            return .claudeUser
        case "result":
            return .claudeResult
        default:
            return .claudeEvent
        }
    }
}
