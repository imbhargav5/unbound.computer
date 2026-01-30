//
//  SessionSubscription.swift
//  unbound-macos
//
//  Per-session Unix socket connection for event streaming.
//  Each session gets its own dedicated NWConnection to the daemon,
//  allowing concurrent subscriptions across multiple sessions.
//
//  The daemon allows only one subscription per connection but supports
//  multiple concurrent connections. This class manages a single connection
//  for a single session's event stream.
//

import Foundation
import Logging
import Network

private let logger = Logger(label: "app.session.subscription")

/// Per-session Unix socket connection that subscribes to daemon events.
final class SessionSubscription: Sendable {

    // MARK: - State

    private let socketPath: String
    private let sessionId: String

    // NWConnection and buffer managed on a dedicated queue
    private let queue = DispatchQueue(label: "session.subscription", qos: .userInitiated)
    private nonisolated(unsafe) var connection: NWConnection?
    private nonisolated(unsafe) var buffer = Data()
    private nonisolated(unsafe) var eventContinuation: AsyncStream<DaemonEvent>.Continuation?
    private nonisolated(unsafe) var isDisconnected = false

    // Pending request continuations for subscribe/unsubscribe handshake
    private nonisolated(unsafe) var pendingRequests: [String: CheckedContinuation<DaemonResponse, Error>] = [:]
    private let requestLock = NSLock()

    // MARK: - Initialization

    init(sessionId: String, socketPath: String = DaemonClient.defaultSocketPath) {
        self.sessionId = sessionId
        self.socketPath = socketPath
    }

    deinit {
        disconnect()
    }

    // MARK: - Connect & Subscribe

    /// Connect to the daemon socket and subscribe to the session.
    /// Returns an AsyncStream of events for this session.
    func subscribe() async throws -> AsyncStream<DaemonEvent> {
        // Open connection
        try await connect()

        // Create event stream and start receiving BEFORE sending the subscribe
        // request. Otherwise sendRequest awaits a response that nobody is reading,
        // causing a deadlock.
        let stream = AsyncStream<DaemonEvent> { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                self.disconnect()
            }
        }
        startReceiving()

        // Send subscribe request (response is now read by the receive loop)
        let request = DaemonRequest(method: .sessionSubscribe, params: ["session_id": sessionId])
        let response = try await sendRequest(request)

        guard response.isSuccess else {
            throw DaemonError.serverError(
                code: response.error?.code ?? -1,
                message: response.error?.message ?? "Subscription failed"
            )
        }

        logger.info("Subscribed to session \(sessionId)")

        return stream
    }

    /// Disconnect the socket. Daemon handles subscriber disconnect gracefully.
    func disconnect() {
        queue.sync {
            guard !isDisconnected else { return }
            isDisconnected = true
        }

        eventContinuation?.finish()
        eventContinuation = nil

        connection?.cancel()
        connection = nil

        // Cancel pending requests
        requestLock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        requestLock.unlock()

        for (_, continuation) in pending {
            continuation.resume(throwing: DaemonError.disconnected)
        }

        logger.debug("Disconnected subscription for session \(sessionId)")
    }

    // MARK: - Private: Connection

    private func connect() async throws {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw DaemonError.socketNotFound
        }

        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()

        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false

            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard !resumed else { return }
                    resumed = true
                    logger.debug("Session subscription connected for \(self?.sessionId ?? "unknown")")
                    continuation.resume()

                case .failed(let error):
                    if !resumed {
                        resumed = true
                        logger.error("Session subscription connection failed: \(error)")
                        continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))
                    } else {
                        logger.error("Session subscription connection lost for \(self?.sessionId ?? "unknown"): \(error)")
                        self?.eventContinuation?.finish()
                    }

                case .cancelled:
                    logger.debug("Session subscription cancelled for \(self?.sessionId ?? "unknown")")

                case .waiting(let error):
                    logger.warning("Session subscription waiting for \(self?.sessionId ?? "unknown"): \(error)")

                default:
                    break
                }
            }

            conn.start(queue: queue)
        }
    }

    // MARK: - Private: Request/Response

    private func sendRequest(_ request: DaemonRequest) async throws -> DaemonResponse {
        let jsonLine = try request.toJsonLine()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DaemonResponse, Error>) in
            requestLock.lock()
            pendingRequests[request.id] = continuation
            requestLock.unlock()

            guard let data = jsonLine.data(using: .utf8) else {
                requestLock.lock()
                pendingRequests.removeValue(forKey: request.id)
                requestLock.unlock()
                continuation.resume(throwing: DaemonError.encodingFailed)
                return
            }

            connection?.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.requestLock.lock()
                    self?.pendingRequests.removeValue(forKey: request.id)
                    self?.requestLock.unlock()
                    continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))
                }
            })
        }
    }

    // MARK: - Private: Receiving

    private func startReceiving() {
        receiveNext()
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                logger.warning("SessionSubscription deallocated during receive")
                return
            }

            if let error {
                logger.error("Receive error on session \(self.sessionId): \(error)")
                self.eventContinuation?.finish()
                return
            }

            if let data {
                logger.debug("Received \(data.count) bytes on session \(self.sessionId)")
                self.buffer.append(data)
                self.processBuffer()
            }

            if isComplete {
                logger.info("Connection completed for session \(self.sessionId)")
                self.eventContinuation?.finish()
                return
            }

            // Continue receiving
            self.receiveNext()
        }
    }

    private func processBuffer() {
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                continue
            }

            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            logger.warning("Failed to encode line as UTF-8 on session \(sessionId)")
            return
        }

        // Try as response first (for subscribe handshake)
        if let response = try? JSONDecoder().decode(DaemonResponse.self, from: data) {
            requestLock.lock()
            if let continuation = pendingRequests.removeValue(forKey: response.id) {
                requestLock.unlock()
                logger.debug("Received RPC response on session \(sessionId)")
                continuation.resume(returning: response)
                return
            }
            requestLock.unlock()
        }

        // Try as event
        if let event = try? JSONDecoder().decode(DaemonEvent.self, from: data) {
            logger.debug("Parsed event type=\(event.type.rawValue) on session \(sessionId)")
            eventContinuation?.yield(event)
            return
        }

        logger.warning("Failed to parse message on session \(sessionId): \(line.prefix(200))")
    }
}
