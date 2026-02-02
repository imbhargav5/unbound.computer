//
//  SessionStreamingClient.swift
//  unbound-macos
//
//  IPC streaming subscription client for real-time session events.
//  Connects to the daemon via Unix socket and receives pushed events.
//

import Foundation
import Logging
import Network

private let logger = Logger(label: "app.session.stream")

/// Per-session streaming client that receives events from the daemon via IPC.
///
/// Unlike the RPC-style DaemonClient, this keeps a persistent connection
/// and receives events as they're pushed by the daemon.
final class SessionStreamingClient: Sendable {

    // MARK: - Properties

    private let sessionId: String
    private let socketPath: String

    // Connection managed on a dedicated queue
    private let queue = DispatchQueue(label: "session.streaming", qos: .userInitiated)
    private nonisolated(unsafe) var connection: NWConnection?
    private nonisolated(unsafe) var eventContinuation: AsyncStream<DaemonEvent>.Continuation?
    private nonisolated(unsafe) var isDisconnected = false
    private nonisolated(unsafe) var receiveTask: Task<Void, Never>?
    private nonisolated(unsafe) var buffer = Data()

    // MARK: - Initialization

    init(sessionId: String, socketPath: String = DaemonClient.defaultSocketPath) {
        self.sessionId = sessionId
        self.socketPath = socketPath
    }

    deinit {
        disconnect()
    }

    // MARK: - Subscribe

    /// Subscribe to session events via IPC streaming.
    ///
    /// Returns an AsyncStream of events. The connection stays open and events
    /// are pushed as they occur. Close by calling `disconnect()` or dropping the stream.
    func subscribe() async throws -> AsyncStream<DaemonEvent> {
        logger.info("Subscribing to session \(sessionId) via IPC streaming")

        // Create connection to Unix socket
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()

        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        // Wait for connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    logger.info("Connected to daemon for session \(self?.sessionId ?? "?")")
                    continuation.resume()
                case .failed(let error):
                    logger.error("Connection failed: \(error)")
                    continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    logger.info("Connection cancelled")
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }

        // Send subscribe request
        let request = DaemonRequest(method: .sessionSubscribe, params: ["session_id": sessionId])
        let requestData = try request.toJsonLine().data(using: .utf8)!

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: requestData, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }

        // Read subscription response
        let responseData = try await readLine()
        guard let responseString = String(data: responseData, encoding: .utf8),
              let response = try? JSONDecoder().decode(DaemonResponse.self, from: responseData) else {
            throw DaemonError.decodingFailed("Invalid subscribe response")
        }

        guard response.isSuccess else {
            throw DaemonError.serverError(
                code: response.error?.code ?? -1,
                message: response.error?.message ?? "Subscribe failed"
            )
        }

        logger.info("Subscribed to session \(sessionId)")

        // Create event stream
        let stream = AsyncStream<DaemonEvent> { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                self.disconnect()
            }
        }

        // Start receiving events
        startReceiving()

        return stream
    }

    /// Disconnect and stop receiving events.
    func disconnect() {
        queue.sync {
            guard !isDisconnected else { return }
            isDisconnected = true
        }

        receiveTask?.cancel()
        receiveTask = nil
        eventContinuation?.finish()
        eventContinuation = nil
        connection?.cancel()
        connection = nil

        logger.debug("Disconnected streaming client for session \(sessionId)")
    }

    // MARK: - Private: Receiving

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    let lineData = try await self.readLine()

                    guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !line.isEmpty else {
                        continue
                    }

                    // Parse as event
                    if let event = self.parseEvent(line) {
                        self.eventContinuation?.yield(event)
                    }
                } catch {
                    if !Task.isCancelled {
                        logger.error("Receive error: \(error)")
                    }
                    break
                }
            }

            self.eventContinuation?.finish()
            logger.info("Event receiving stopped for session \(self.sessionId)")
        }
    }

    private func readLine() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            guard let conn = connection else {
                continuation.resume(throwing: DaemonError.disconnected)
                return
            }

            readUntilNewline(conn: conn, continuation: continuation)
        }
    }

    private func readUntilNewline(
        conn: NWConnection,
        continuation: CheckedContinuation<Data, Error>
    ) {
        // Check if we already have a complete line in the buffer
        if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])
            continuation.resume(returning: Data(lineData))
            return
        }

        // Read more data
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                continuation.resume(throwing: DaemonError.disconnected)
                return
            }

            if let error {
                continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))
                return
            }

            if isComplete {
                continuation.resume(throwing: DaemonError.disconnected)
                return
            }

            if let data {
                self.buffer.append(data)
            }

            // Recursively check for newline
            self.readUntilNewline(conn: conn, continuation: continuation)
        }
    }

    private func parseEvent(_ json: String) -> DaemonEvent? {
        guard let data = json.data(using: .utf8) else { return nil }

        do {
            // Try to decode as a typed event
            struct RawEvent: Codable {
                let type: String
                let session_id: String
                let data: [String: AnyCodableValue]
                let sequence: Int64
            }

            let raw = try JSONDecoder().decode(RawEvent.self, from: data)
            let eventType = DaemonEventType(rawValue: raw.type) ?? .claudeEvent

            return DaemonEvent(
                type: eventType,
                sessionId: raw.session_id,
                data: raw.data,
                sequence: raw.sequence
            )
        } catch {
            logger.warning("Failed to parse event: \(error), json: \(json.prefix(100))")
            return nil
        }
    }
}
