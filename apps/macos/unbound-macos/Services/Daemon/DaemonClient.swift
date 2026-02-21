//
//  DaemonClient.swift
//  unbound-macos
//
//  Unix socket client for communicating with the Unbound daemon.
//  Uses NDJSON protocol (newline-delimited JSON) for request/response.
//  This is a pure RPC client. Subscriptions are handled by SessionSubscription.
//

import Foundation
import Logging
import Network

private let logger = Logger(label: "app.daemon")

// MARK: - Daemon Client

/// Client for communicating with the Unbound daemon over Unix socket.
@Observable
final class DaemonClient {
    // MARK: - Singleton

    static let shared = DaemonClient()

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private(set) var connectionState: ConnectionState = .disconnected

    // MARK: - Socket Path

    /// Default daemon socket path.
    static var defaultSocketPath: String {
        Config.socketPath
    }

    private let socketPath: String

    // MARK: - Connection

    private var connection: NWConnection?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Request/Response Correlation

    private var pendingRequests: [String: CheckedContinuation<DaemonResponse, Error>] = [:]
    private let requestLock = NSLock()

    // MARK: - Reconnection

    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0

    // MARK: - Initialization

    private init(socketPath: String = DaemonClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    // MARK: - Connection Timeout

    private let connectionTimeout: TimeInterval = 10.0

    // MARK: - Connection Management

    /// Connect to the daemon with timeout protection.
    func connect() async throws {
        guard connectionState != .connected else { return }

        connectionState = .connecting
        logger.info("Connecting to daemon at \(socketPath)")

        // Check if socket exists
        guard FileManager.default.fileExists(atPath: socketPath) else {
            connectionState = .failed("Socket not found")
            throw DaemonError.socketNotFound
        }

        // Connect with timeout to prevent indefinite hangs
        try await connectWithTimeout()
    }

    /// Connect with a timeout wrapper.
    private func connectWithTimeout() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.rawConnect()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.connectionTimeout))
                throw DaemonError.requestTimeout
            }

            // Wait for first to complete
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// Raw connection logic without timeout.
    private func rawConnect() async throws {
        // Create Unix socket endpoint
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()

        connection = NWConnection(to: endpoint, using: parameters)

        // Wait for connection with proper handling of ALL states
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Track whether we've already resumed to prevent multiple resumptions
            var hasResumed = false

            connection?.stateUpdateHandler = { [weak self] state in
                guard let self, !hasResumed else { return }

                switch state {
                case .ready:
                    hasResumed = true
                    logger.info("Connected to daemon")
                    self.connectionState = .connected
                    self.reconnectAttempt = 0
                    self.startReceiving()
                    continuation.resume()

                case .failed(let error):
                    hasResumed = true
                    logger.error("Connection failed: \(error)")
                    self.connectionState = .failed(error.localizedDescription)
                    continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))

                case .cancelled:
                    hasResumed = true
                    logger.info("Connection cancelled")
                    self.connectionState = .disconnected
                    continuation.resume(throwing: DaemonError.disconnected)

                case .waiting(let error):
                    // Connection is waiting - daemon socket exists but nothing listening
                    // This happens when daemon crashed and left stale socket
                    hasResumed = true
                    logger.warning("Connection waiting (daemon not responding): \(error)")
                    self.connectionState = .failed("Daemon not responding")
                    continuation.resume(throwing: DaemonError.connectionFailed("Daemon not responding: \(error)"))

                case .preparing:
                    logger.debug("Connection preparing")

                case .setup:
                    logger.debug("Connection setup")

                @unknown default:
                    break
                }
            }

            connection?.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Disconnect from the daemon.
    func disconnect() {
        logger.info("Disconnecting from daemon")
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        connectionState = .disconnected

        // Cancel all pending requests
        requestLock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        requestLock.unlock()

        for (_, continuation) in pending {
            continuation.resume(throwing: DaemonError.disconnected)
        }
    }

    /// Check if daemon socket exists (quick check).
    /// Note: This only checks if the socket file exists, not if daemon is responsive.
    /// Use `isDaemonAlive()` for a proper health check.
    func isDaemonRunning() -> Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    /// Check if daemon is actually alive and responsive (async health check).
    /// This attempts a real connection with a short timeout.
    func isDaemonAlive() async -> Bool {
        // First check socket exists
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return false
        }

        // If already connected, verify connection is still good
        if connectionState.isConnected {
            return true
        }

        // Try a quick health check with timeout
        do {
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    // Try to connect and call health endpoint
                    try await self.connect()
                    _ = try await self.call(method: .health)
                    return true
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(3.0))
                    return false
                }

                let result = try await group.next() ?? false
                group.cancelAll()
                return result
            }
        } catch {
            logger.debug("Health check failed: \(error)")
            return false
        }
    }

    // MARK: - Request/Response

    /// Send a request and wait for response.
    func call(method: DaemonMethod, params: [String: Any]? = nil) async throws -> DaemonResponse {
        // Ensure connected
        if !connectionState.isConnected {
            try await connect()
        }

        let request = DaemonRequest(method: method, params: params)
        let jsonLine = try request.toJsonLine()

        logger.debug("Sending request: \(method.rawValue) id=\(request.id)")

        // Register pending request
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DaemonResponse, Error>) in
            requestLock.lock()
            pendingRequests[request.id] = continuation
            requestLock.unlock()

            // Send the request
            guard let data = jsonLine.data(using: .utf8) else {
                requestLock.lock()
                pendingRequests.removeValue(forKey: request.id)
                requestLock.unlock()
                continuation.resume(throwing: DaemonError.encodingFailed)
                return
            }

            connection?.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    logger.error("Send failed: \(error)")
                    self?.requestLock.lock()
                    self?.pendingRequests.removeValue(forKey: request.id)
                    self?.requestLock.unlock()
                    continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))
                }
            })
        }

        // Check for errors
        if let error = response.error {
            switch error.code {
            case DaemonErrorCode.notAuthenticated:
                throw DaemonError.notAuthenticated
            case DaemonErrorCode.notFound:
                throw DaemonError.notFound(error.message)
            case DaemonErrorCode.conflict:
                throw DaemonError.conflict(currentRevision: decodeConflictRevision(from: error.data))
            default:
                throw DaemonError.serverError(code: error.code, message: error.message)
            }
        }

        return response
    }

    private func decodeConflictRevision(from data: AnyCodableValue?) -> DaemonFileRevision? {
        guard let payload = data?.value as? [String: Any],
              let revisionValue = payload["current_revision"],
              JSONSerialization.isValidJSONObject(revisionValue),
              let revisionData = try? JSONSerialization.data(withJSONObject: revisionValue) else {
            return nil
        }
        return try? JSONDecoder().decode(DaemonFileRevision.self, from: revisionData)
    }

    // MARK: - Receiving Data

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }

            var buffer = Data()

            while !Task.isCancelled {
                do {
                    guard let data = try await self.receiveData() else {
                        continue
                    }

                    buffer.append(data)

                    // Process complete lines (NDJSON)
                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer[buffer.startIndex..<newlineIndex]
                        buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                        if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                            self.processLine(line)
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        logger.error("Receive error: \(error)")
                        await self.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    private func receiveData() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if isComplete {
                    continuation.resume(throwing: DaemonError.disconnected)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private func processLine(_ line: String) {
        // Parse as response and match to pending request
        if let data = line.data(using: .utf8),
           let response = try? JSONDecoder().decode(DaemonResponse.self, from: data) {
            requestLock.lock()
            if let continuation = pendingRequests.removeValue(forKey: response.id) {
                requestLock.unlock()
                logger.debug("Received response for request \(response.id)")
                continuation.resume(returning: response)
                return
            }
            requestLock.unlock()
        }

        logger.warning("Unknown message format: \(line.prefix(100))")
    }

    // MARK: - Reconnection

    private func handleDisconnect() async {
        guard connectionState.isConnected || connectionState == .connecting else { return }

        connectionState = .disconnected
        connection?.cancel()
        connection = nil

        // Notify pending requests
        requestLock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        requestLock.unlock()

        for (_, continuation) in pending {
            continuation.resume(throwing: DaemonError.disconnected)
        }

        // Attempt reconnection
        await attemptReconnect()
    }

    private func attemptReconnect() async {
        guard reconnectAttempt < maxReconnectAttempts else {
            logger.error("Max reconnection attempts reached")
            connectionState = .failed("Max reconnection attempts reached")
            return
        }

        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)

        // Exponential backoff
        let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)
        logger.info("Reconnecting in \(delay)s (attempt \(reconnectAttempt)/\(maxReconnectAttempts))")

        do {
            try await Task.sleep(for: .seconds(delay))
            try await connect()
        } catch {
            if !Task.isCancelled {
                logger.error("Reconnection failed: \(error)")
                await attemptReconnect()
            }
        }
    }

    /// Reset reconnection state (call before manual connect).
    func resetReconnectState() {
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
    }
}
