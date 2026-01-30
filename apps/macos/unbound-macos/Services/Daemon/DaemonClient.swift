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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.unbound/daemon.sock"
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

    // MARK: - Connection Management

    /// Connect to the daemon.
    func connect() async throws {
        guard connectionState != .connected else { return }

        connectionState = .connecting
        logger.info("Connecting to daemon at \(socketPath)")

        // Check if socket exists
        guard FileManager.default.fileExists(atPath: socketPath) else {
            connectionState = .failed("Socket not found")
            throw DaemonError.socketNotFound
        }

        // Create Unix socket endpoint
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()

        connection = NWConnection(to: endpoint, using: parameters)

        // Wait for connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    logger.info("Connected to daemon")
                    self.connectionState = .connected
                    self.reconnectAttempt = 0
                    self.startReceiving()
                    continuation.resume()

                case .failed(let error):
                    logger.error("Connection failed: \(error)")
                    self.connectionState = .failed(error.localizedDescription)
                    continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))

                case .cancelled:
                    logger.info("Connection cancelled")
                    self.connectionState = .disconnected

                case .waiting(let error):
                    logger.warning("Connection waiting: \(error)")

                default:
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

    /// Check if daemon is running (socket exists).
    func isDaemonRunning() -> Bool {
        FileManager.default.fileExists(atPath: socketPath)
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
            default:
                throw DaemonError.serverError(code: error.code, message: error.message)
            }
        }

        return response
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
