//
//  OutboxModels.swift
//  unbound-macos
//
//  Data models for conversation event outbox pattern.
//

import Foundation

// MARK: - Outbox Event

/// Represents a conversation event in the outbox queue
/// All events now reference a message by ID - the message contains the encrypted payload
/// Note: eventType is stored inside the encrypted EventPayload content, not as a separate column
struct OutboxEvent: Codable, Identifiable, Sendable {
    let id: String  // event_id (ULID)
    let sessionId: String
    let sequenceNumber: UInt64
    var relaySendBatchId: String?  // Batch ID for HTTP send grouping (renamed from batchId)
    // eventType is now extracted from the decrypted EventPayload when needed
    let messageId: String  // Reference to encrypted message row (REQUIRED)
    var status: OutboxEventStatus
    var retryCount: Int
    var lastError: String?
    let createdAt: Date
    var sentAt: Date?
    var ackedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "event_id"
        case sessionId = "session_id"
        case sequenceNumber = "sequence_number"
        case relaySendBatchId = "relay_send_batch_id"
        case messageId = "message_id"
        case status
        case retryCount = "retry_count"
        case lastError = "last_error"
        case createdAt = "created_at"
        case sentAt = "sent_at"
        case ackedAt = "acked_at"
    }
}

// MARK: - Outbox Event Status

enum OutboxEventStatus: String, Codable, Sendable {
    case pending
    case sent
    case acked
    case failed
}

// MARK: - Outbox Error

/// Errors that can occur in the outbox system
enum OutboxError: Error, LocalizedError {
    case missingConfiguration
    case databaseError(String)
    case encodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Missing required configuration (RELAY_HTTP_URL)"
        case let .databaseError(message):
            return "Database error: \(message)"
        case let .encodingError(message):
            return "Encoding error: \(message)"
        case let .networkError(message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Outbox Batch

/// Represents a batch of events to be sent together via HTTP
struct OutboxBatch: Sendable {
    let relaySendBatchId: String  // Renamed from batchId
    let sessionId: String
    let events: [OutboxEvent]
    let sequenceRange: ClosedRange<UInt64>

    var eventCount: Int {
        events.count
    }

    init(relaySendBatchId: String, sessionId: String, events: [OutboxEvent]) {
        self.relaySendBatchId = relaySendBatchId
        self.sessionId = sessionId
        self.events = events
        if let first = events.first?.sequenceNumber,
           let last = events.last?.sequenceNumber
        {
            self.sequenceRange = first...last
        } else {
            self.sequenceRange = 0...0
        }
    }
}

// MARK: - Outbox Stats

/// Statistics about the outbox queue
struct OutboxStats: Sendable {
    let pendingCount: Int
    let sentCount: Int
    let inFlightBatches: Int
    let oldestPendingSequence: UInt64?
    let oldestPendingAge: TimeInterval?

    var isHealthy: Bool {
        // Alert conditions
        let hasTooManyPending = pendingCount > 500
        let hasStaleEvents = (oldestPendingAge ?? 0) > 60  // 60 seconds
        let hasStuckBatches = inFlightBatches > 0 && (oldestPendingAge ?? 0) > 30

        return !hasTooManyPending && !hasStaleEvents && !hasStuckBatches
    }
}

// MARK: - Session Event Payload

/// Represents a conversation event to be sent to relay
/// Matches the server's BaseUnboundEvent + SessionEvent schema
struct SessionEventPayload: Codable, Sendable {
    let opcode: String               // "EVENT"
    let eventId: String              // ULID format
    let plane: String                // "SESSION"
    let sessionId: String            // Session ULID
    /// Session event type:
    /// - "REMOTE_COMMAND": Commands from iOS/web sent via relay to executor
    /// - "EXECUTOR_UPDATE": Updates from executor sent to iOS/web viewers
    /// - "LOCAL_EXECUTION_COMMAND": Commands executed directly on executor (not sent to relay)
    let sessionEventType: String
    let createdAt: Double            // Unix MILLISECONDS
    let type: String
    let payload: [String: OutboxAnyCodable]

    enum CodingKeys: String, CodingKey {
        case opcode
        case eventId
        case plane
        case sessionId
        case sessionEventType
        case createdAt
        case type
        case payload
    }
}

// MARK: - Relay Request/Response (Legacy - Unencrypted)

/// Request payload sent to relay HTTP endpoint (legacy /events endpoint)
struct RelayEventsRequest: Codable, Sendable {
    let sessionId: String
    let deviceToken: String
    let batchId: String
    let events: [SessionEventPayload]
}

/// Response from relay HTTP endpoint
struct RelayEventsResponse: Codable, Sendable {
    let success: Bool
    let batchId: String
    let sessionId: String
    let totalEvents: Int
    let conversationEvents: Int
    let streamedIds: Int
    let message: String?
    let timestamp: TimeInterval
}

// MARK: - Relay Messages Request/Response (New - Encrypted)

/// Encrypted message payload for relay
/// Contains role (unencrypted) and content (encrypted) for end-to-end encryption
struct SessionMessagePayload: Codable, Sendable {
    let eventId: String              // ULID format
    let sessionId: String            // Session ID
    let messageId: String            // Message ID (for deduplication)
    let role: String                 // "user", "assistant", "system" (unencrypted)
    let sequenceNumber: Int          // For ordering
    let createdAt: Double            // Unix milliseconds
    let contentEncrypted: String     // Base64-encoded encrypted content
    let contentNonce: String         // Base64-encoded nonce for decryption
    let sessionEventType: String     // REMOTE_COMMAND, EXECUTOR_UPDATE, LOCAL_EXECUTION_COMMAND
    let eventType: String?           // Optional: event type hint for filtering
}

/// Request payload for encrypted messages (new /messages endpoint)
struct RelayMessagesRequest: Codable, Sendable {
    let sessionId: String
    let deviceToken: String
    let batchId: String
    let messages: [SessionMessagePayload]
}

/// Response from relay /messages endpoint
struct RelayMessagesResponse: Codable, Sendable {
    let success: Bool
    let batchId: String
    let sessionId: String
    let totalMessages: Int
    let conversationMessages: Int
    let remoteCommands: Int
    let executorUpdates: Int
    let streamedIds: Int
    let message: String?
    let timestamp: TimeInterval
}

// MARK: - OutboxAnyCodable Helper

/// Type-erased Codable wrapper for arbitrary JSON values
struct OutboxAnyCodable: Codable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([OutboxAnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: OutboxAnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { OutboxAnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { OutboxAnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported type for encoding"
                )
            )
        }
    }
}
