import Foundation

enum RelayError: LocalizedError {
    case notConnected
    case authenticationFailed(String)
    case serverError(code: String, message: String)
    case connectionClosed
    case encodingFailed
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WebSocket is not connected"
        case .authenticationFailed(let reason):
            return "Failed to authenticate with relay server: \(reason)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .connectionClosed:
            return "WebSocket connection was closed"
        case .encodingFailed:
            return "Failed to encode command"
        case .decodingFailed(let reason):
            return "Failed to decode event: \(reason)"
        }
    }
}

actor RelayWebSocketService {
    static let shared = RelayWebSocketService()

    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    // Event stream for consumers
    private var eventContinuation: AsyncStream<RelayEvent>.Continuation?
    private(set) var eventStream: AsyncStream<RelayEvent>?

    init() {
        let stream = AsyncStream<RelayEvent> { continuation in
            self.eventContinuation = continuation
        }
        self.eventStream = stream
    }

    private func setupEventStream() {
        let stream = AsyncStream<RelayEvent> { continuation in
            eventContinuation = continuation
        }
        eventStream = stream
    }

    // MARK: - Connection Management

    func connect() async throws {
        guard !isConnected else {
            Config.log("⚠️ Already connected to relay")
            return
        }

        Config.log("🔌 Connecting to relay WebSocket: \(Config.relayWebSocketURL)")

        guard let url = URL(string: Config.relayWebSocketURL) else {
            throw RelayError.serverError(code: "INVALID_URL", message: "Invalid WebSocket URL")
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        reconnectAttempts = 0

        Config.log("✅ Connected to relay WebSocket")

        // Start receiving messages
        Task {
            await receiveMessages()
        }
    }

    func disconnect() async throws {
        Config.log("🔌 Disconnecting from relay WebSocket")

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false

        eventContinuation?.finish()
        setupEventStream() // Reset stream for next connection

        Config.log("✅ Disconnected from relay WebSocket")
    }

    // MARK: - Commands

    func authenticate(token: String, deviceId: String) async throws {
        Config.log("🔐 Authenticating with relay (deviceId: \(deviceId))")

        let command = RelayCommand.authenticate(token: token, deviceId: deviceId)
        try await send(command)
    }

    func subscribe(sessionId: String) async throws {
        Config.log("📡 Subscribing to session: \(sessionId)")

        let command = RelayCommand.subscribe(sessionId: sessionId)
        try await send(command)
    }

    func unsubscribe(sessionId: String) async throws {
        Config.log("📡 Unsubscribing from session: \(sessionId)")

        let command = RelayCommand.unsubscribe(sessionId: sessionId)
        try await send(command)
    }

    func joinSession(sessionId: String, role: DeviceRole, permission: Permission?) async throws {
        Config.log("🚪 Joining session \(sessionId) with role \(role.rawValue)")

        let command = RelayCommand.joinSession(sessionId: sessionId, role: role, permission: permission)
        try await send(command)
    }

    func leaveSession(sessionId: String) async throws {
        Config.log("🚪 Leaving session: \(sessionId)")

        let command = RelayCommand.leaveSession(sessionId: sessionId)
        try await send(command)
    }

    // MARK: - Low-level Send/Receive

    private func send(_ command: RelayCommand) async throws {
        guard let webSocketTask, isConnected else {
            throw RelayError.notConnected
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        guard let data = try? encoder.encode(command) else {
            throw RelayError.encodingFailed
        }

        let message = URLSessionWebSocketTask.Message.data(data)

        do {
            try await webSocketTask.send(message)
            Config.log("📤 Sent command: \(String(data: data, encoding: .utf8) ?? "unknown")")
        } catch {
            Config.log("❌ Failed to send command: \(error)")
            throw error
        }
    }

    private func receiveMessages() async {
        while isConnected, let webSocketTask {
            do {
                let message = try await webSocketTask.receive()

                switch message {
                case .data(let data):
                    handleMessage(data)

                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        handleMessage(data)
                    }

                @unknown default:
                    Config.log("⚠️ Unknown message type received")
                }

            } catch {
                Config.log("❌ WebSocket receive error: \(error)")
                isConnected = false

                eventContinuation?.yield(.error(
                    code: "CONNECTION_ERROR",
                    message: error.localizedDescription
                ))

                // Attempt reconnection
                await attemptReconnect()
                break
            }
        }
    }

    private func handleMessage(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        do {
            let event = try decoder.decode(RelayEvent.self, from: data)

            Config.log("📥 Received event: \(event)")

            eventContinuation?.yield(event)

            // Handle auth failures by disconnecting
            if case .authFailure = event {
                Task {
                    try? await disconnect()
                }
            }

        } catch {
            Config.log("❌ Failed to decode relay event: \(error)")

            // Try to decode as raw JSON for debugging
            if let json = try? JSONSerialization.jsonObject(with: data) {
                Config.log("📄 Raw JSON: \(json)")
            }

            eventContinuation?.yield(.error(
                code: "DECODE_ERROR",
                message: error.localizedDescription
            ))
        }
    }

    // MARK: - Reconnection Logic

    private func attemptReconnect() async {
        guard reconnectAttempts < maxReconnectAttempts else {
            Config.log("❌ Max reconnection attempts reached")
            eventContinuation?.yield(.error(
                code: "MAX_RECONNECT_ATTEMPTS",
                message: "Failed to reconnect after \(maxReconnectAttempts) attempts"
            ))
            return
        }

        reconnectAttempts += 1

        // Exponential backoff with max 30 seconds
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        Config.log("🔄 Attempting reconnection in \(delay)s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")

        try? await Task.sleep(for: .seconds(delay))

        do {
            try await connect()
            Config.log("✅ Reconnected successfully")
        } catch {
            Config.log("❌ Reconnection failed: \(error)")
            await attemptReconnect()
        }
    }
}
