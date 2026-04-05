//
//  DaemonConnectionManager.swift
//  unbound-macos
//
//  Actor that manages daemon connection lifecycle with circuit breaker pattern.
//  Provides resilient connection handling with automatic recovery.
//

import Foundation
import Logging
import Network

private let logger = Logger(label: "app.daemon.connection")

// MARK: - Circuit Breaker

/// Circuit breaker to prevent cascading failures when daemon is unavailable.
actor CircuitBreaker {
    enum State {
        case closed       // Normal operation, requests allowed
        case open         // Failing, reject requests immediately
        case halfOpen     // Testing if service recovered
    }

    private(set) var state: State = .closed
    private var failureCount = 0
    private var lastFailureTime: Date?
    private var consecutiveSuccesses = 0

    private let failureThreshold: Int
    private let resetTimeout: TimeInterval
    private let halfOpenSuccessThreshold: Int

    init(
        failureThreshold: Int = 3,
        resetTimeout: TimeInterval = 30.0,
        halfOpenSuccessThreshold: Int = 2
    ) {
        self.failureThreshold = failureThreshold
        self.resetTimeout = resetTimeout
        self.halfOpenSuccessThreshold = halfOpenSuccessThreshold
    }

    /// Check if a request should be allowed through.
    func shouldAllowRequest() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            // Check if enough time has passed to try again
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= resetTimeout {
                state = .halfOpen
                consecutiveSuccesses = 0
                logger.info("Circuit breaker transitioning to half-open state")
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }

    /// Record a successful operation.
    func recordSuccess() {
        failureCount = 0
        lastFailureTime = nil

        switch state {
        case .halfOpen:
            consecutiveSuccesses += 1
            if consecutiveSuccesses >= halfOpenSuccessThreshold {
                state = .closed
                logger.info("Circuit breaker closed after successful recovery")
            }
        case .open:
            state = .closed
            logger.info("Circuit breaker closed")
        case .closed:
            break
        }
    }

    /// Record a failed operation.
    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()
        consecutiveSuccesses = 0

        if state == .halfOpen {
            state = .open
            logger.warning("Circuit breaker reopened after failure in half-open state")
        } else if failureCount >= failureThreshold {
            state = .open
            logger.warning("Circuit breaker opened after \(failureCount) failures")
        }
    }

    /// Reset the circuit breaker to closed state.
    func reset() {
        state = .closed
        failureCount = 0
        lastFailureTime = nil
        consecutiveSuccesses = 0
        logger.info("Circuit breaker reset")
    }

    /// Get time remaining until circuit breaker allows retry (0 if already allowed).
    func timeUntilRetry() -> TimeInterval {
        guard state == .open, let lastFailure = lastFailureTime else {
            return 0
        }
        let elapsed = Date().timeIntervalSince(lastFailure)
        return max(0, resetTimeout - elapsed)
    }
}

// MARK: - Connection Manager

/// Actor that manages daemon connection with circuit breaker and health checks.
actor DaemonConnectionManager {
    // MARK: - Connection State

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed(String)
        case circuitOpen(retryIn: TimeInterval)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // MARK: - Properties

    private(set) var state: State = .disconnected
    private var connection: NWConnection?
    private var receiveTask: Task<Void, Never>?

    private let socketPath: String
    private let circuitBreaker: CircuitBreaker
    private let connectionTimeout: TimeInterval
    private let healthCheckInterval: TimeInterval

    private var healthCheckTask: Task<Void, Never>?
    private var pendingRequests: [String: CheckedContinuation<DaemonResponse, Error>] = [:]

    // Reconnection state
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0

    // State change callback
    private var stateChangeHandler: ((State) -> Void)?

    // MARK: - Initialization

    init(
        socketPath: String = DaemonClient.defaultSocketPath,
        connectionTimeout: TimeInterval = 10.0,
        healthCheckInterval: TimeInterval = 30.0
    ) {
        self.socketPath = socketPath
        self.connectionTimeout = connectionTimeout
        self.healthCheckInterval = healthCheckInterval
        self.circuitBreaker = CircuitBreaker()
    }

    // MARK: - State Change Handler

    func setStateChangeHandler(_ handler: @escaping (State) -> Void) {
        self.stateChangeHandler = handler
    }

    private func updateState(_ newState: State) {
        state = newState
        stateChangeHandler?(newState)
    }

    // MARK: - Connection Management

    /// Connect to the daemon with circuit breaker protection.
    func connect() async throws {
        // Check circuit breaker
        let allowed = await circuitBreaker.shouldAllowRequest()
        if !allowed {
            let retryIn = await circuitBreaker.timeUntilRetry()
            updateState(.circuitOpen(retryIn: retryIn))
            throw DaemonError.connectionFailed("Circuit breaker open, retry in \(Int(retryIn))s")
        }

        guard state != .connected else { return }

        updateState(.connecting)
        logger.info("Connecting to daemon at \(socketPath)")

        do {
            try await connectWithTimeout()
            await circuitBreaker.recordSuccess()
            updateState(.connected)
            reconnectAttempt = 0
            startHealthChecks()
            logger.info("Connected to daemon")
        } catch {
            await circuitBreaker.recordFailure()
            let errorMessage = error.localizedDescription
            updateState(.failed(errorMessage))
            throw error
        }
    }

    /// Connect with a timeout to prevent indefinite hangs.
    private func connectWithTimeout() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.rawConnect()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.connectionTimeout))
                throw DaemonError.requestTimeout
            }

            // Wait for first to complete (either success or timeout)
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// Raw connection without timeout wrapper.
    private func rawConnect() async throws {
        // Check if socket exists
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw DaemonError.socketNotFound
        }

        // Create Unix socket endpoint
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()

        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        // Wait for connection with proper state handling
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false

            conn.stateUpdateHandler = { [weak self] state in
                guard !hasResumed else { return }

                switch state {
                case .ready:
                    hasResumed = true
                    logger.debug("NWConnection ready")
                    continuation.resume()

                case .failed(let error):
                    hasResumed = true
                    logger.error("NWConnection failed: \(error)")
                    continuation.resume(throwing: DaemonError.connectionFailed(error.localizedDescription))

                case .cancelled:
                    hasResumed = true
                    logger.info("NWConnection cancelled")
                    continuation.resume(throwing: DaemonError.disconnected)

                case .waiting(let error):
                    // Connection is waiting - this means daemon socket exists but nothing is listening
                    hasResumed = true
                    logger.warning("NWConnection waiting (daemon not responding): \(error)")
                    continuation.resume(throwing: DaemonError.connectionFailed("Daemon not responding: \(error)"))

                case .preparing:
                    logger.debug("NWConnection preparing")

                case .setup:
                    logger.debug("NWConnection setup")

                @unknown default:
                    break
                }
            }

            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Disconnect from the daemon.
    func disconnect() {
        logger.info("Disconnecting from daemon")
        healthCheckTask?.cancel()
        healthCheckTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
        updateState(.disconnected)

        // Cancel all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: DaemonError.disconnected)
        }
        pendingRequests.removeAll()
    }

    /// Reset circuit breaker and connection state for manual retry.
    func reset() async {
        disconnect()
        await circuitBreaker.reset()
        reconnectAttempt = 0
        updateState(.disconnected)
    }

    // MARK: - Health Checks

    /// Perform a health check to verify daemon is responsive.
    func healthCheck() async -> Bool {
        guard state.isConnected, let conn = connection else {
            return false
        }

        // Simple connectivity check - verify connection is still ready
        if case .ready = conn.state {
            return true
        }

        return false
    }

    /// Start periodic health checks.
    private func startHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.healthCheckInterval ?? 30))

                guard let self, !Task.isCancelled else { break }

                let healthy = await self.healthCheck()
                if !healthy {
                    logger.warning("Health check failed, triggering reconnect")
                    await self.handleDisconnect()
                    break
                }
            }
        }
    }

    // MARK: - Reconnection

    /// Handle disconnection and attempt reconnection.
    func handleDisconnect() async {
        guard state.isConnected || state == .connecting else { return }

        updateState(.disconnected)
        connection?.cancel()
        connection = nil

        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: DaemonError.disconnected)
        }
        pendingRequests.removeAll()

        // Attempt reconnection
        await attemptReconnect()
    }

    /// Attempt to reconnect with exponential backoff.
    private func attemptReconnect() async {
        guard reconnectAttempt < maxReconnectAttempts else {
            logger.error("Max reconnection attempts reached")
            updateState(.failed("Max reconnection attempts reached"))
            return
        }

        reconnectAttempt += 1
        updateState(.reconnecting(attempt: reconnectAttempt))

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

    // MARK: - Request Handling

    /// Execute a request through the circuit breaker.
    func executeRequest<T>(
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        // Check circuit breaker
        let allowed = await circuitBreaker.shouldAllowRequest()
        if !allowed {
            let retryIn = await circuitBreaker.timeUntilRetry()
            throw DaemonError.connectionFailed("Circuit breaker open, retry in \(Int(retryIn))s")
        }

        do {
            let result = try await operation()
            await circuitBreaker.recordSuccess()
            return result
        } catch {
            await circuitBreaker.recordFailure()
            throw error
        }
    }

    // MARK: - Connection Access

    /// Get the current connection if available.
    func getConnection() -> NWConnection? {
        guard state.isConnected else { return nil }
        return connection
    }

    /// Check if daemon socket exists (quick check, doesn't verify daemon is alive).
    nonisolated func socketExists() -> Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }
}

// MARK: - Daemon Connection Manager Error Extension

extension DaemonError {
    static var circuitOpen: DaemonError {
        .connectionFailed("Circuit breaker is open - too many recent failures")
    }
}
