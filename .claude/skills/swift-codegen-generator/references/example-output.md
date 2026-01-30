# Example Output Reference

This file contains the current `TransportReliability.swift` as a reference for code generation. Preserve existing type names when regenerating.

## Current TransportReliability.swift

```swift
// This file was generated from Zod schemas, do not modify it directly.
// Run `pnpm codegen:swift` to regenerate.

import Foundation

// MARK: - Enums

public enum Opcode: String, Codable {
    case event = "EVENT"
    case ack = "ACK"
}

public enum Plane: String, Codable {
    case handshake = "HANDSHAKE"
    case session = "SESSION"
}

public enum SessionEventType: String, Codable {
    case remoteCommand = "REMOTE_COMMAND"
    case executorUpdate = "EXECUTOR_UPDATE"
}

public enum HandshakeEventType: String, Codable {
    case pairRequest = "PAIR_REQUEST"
    case pairAccepted = "PAIR_ACCEPTED"
    case sessionCreated = "SESSION_CREATED"
}

public enum SessionEventTypeValue: String, Codable {
    case createWorktree = "CREATE_WORKTREE"
    case fixConflicts = "FIX_CONFLICTS"
    case executionStarted = "EXECUTION_STARTED"
    case outputChunk = "OUTPUT_CHUNK"
    case executionCompleted = "EXECUTION_COMPLETED"
}

// MARK: - Payload Types

public struct PairRequestPayload: Codable, Equatable, Sendable {
    public let remoteDeviceName: String
    public let remoteDeviceId: String
    public let remotePublicKey: String

    public init(remoteDeviceName: String, remoteDeviceId: String, remotePublicKey: String) {
        self.remoteDeviceName = remoteDeviceName
        self.remoteDeviceId = remoteDeviceId
        self.remotePublicKey = remotePublicKey
    }
}

public struct PairAcceptedPayload: Codable, Equatable, Sendable {
    public let executorDeviceId: String
    public let executorPublicKey: String
    public let executorDeviceName: String

    public init(executorDeviceId: String, executorPublicKey: String, executorDeviceName: String) {
        self.executorDeviceId = executorDeviceId
        self.executorPublicKey = executorPublicKey
        self.executorDeviceName = executorDeviceName
    }
}

public struct CreateWorktreePayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let branch: String

    public init(repoId: String, branch: String) {
        self.repoId = repoId
        self.branch = branch
    }
}

public struct FixConflictsPayload: Codable, Equatable, Sendable {
    public let repoId: String
    public let worktreeId: String

    public init(repoId: String, worktreeId: String) {
        self.repoId = repoId
        self.worktreeId = worktreeId
    }
}

public struct OutputChunkPayload: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ExecutionCompletedPayload: Codable, Equatable, Sendable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}

public struct EmptyPayload: Codable, Equatable, Sendable {
    public init() {}
}

// MARK: - Concrete Event Types

public struct PairRequestEvent: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: HandshakeEventType
    public let plane: Plane
    public let sessionId: String?
    public let payload: PairRequestPayload

    public init(eventId: String, createdAt: Double, payload: PairRequestPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .pairRequest
        self.plane = .handshake
        self.sessionId = nil
        self.payload = payload
    }
}

public struct PairAcceptedEvent: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: HandshakeEventType
    public let plane: Plane
    public let sessionId: String?
    public let payload: PairAcceptedPayload

    public init(eventId: String, createdAt: Double, payload: PairAcceptedPayload) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .pairAccepted
        self.plane = .handshake
        self.sessionId = nil
        self.payload = payload
    }
}

public struct SessionCreatedEvent: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String
    public let createdAt: Double
    public let type: HandshakeEventType
    public let plane: Plane
    public let sessionId: String
    public let payload: EmptyPayload

    public init(eventId: String, createdAt: Double, sessionId: String) {
        self.opcode = .event
        self.eventId = eventId
        self.createdAt = createdAt
        self.type = .sessionCreated
        self.plane = .handshake
        self.sessionId = sessionId
        self.payload = EmptyPayload()
    }
}

public struct AckFrame: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String

    public init(eventId: String) {
        self.opcode = .ack
        self.eventId = eventId
    }
}

// MARK: - Discriminated Unions

public enum HandshakeEvent: Equatable, Sendable {
    case pairRequest(PairRequestEvent)
    case pairAccepted(PairAcceptedEvent)
    case sessionCreated(SessionCreatedEvent)
}

public enum SessionEvent: Equatable, Sendable {
    case createWorktree(CreateWorktreeCommand)
    case fixConflicts(FixConflictsCommand)
    case executionStarted(ExecutionStartedUpdate)
    case outputChunk(OutputChunkUpdate)
    case executionCompleted(ExecutionCompletedUpdate)
}

public enum UnboundEvent: Equatable, Sendable {
    case handshake(HandshakeEvent)
    case session(SessionEvent)
}

public enum AnyEvent: Equatable, Sendable {
    case event(UnboundEvent)
    case ack(AckFrame)
}

// MARK: - Codable Extensions for Discriminated Unions

extension HandshakeEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(HandshakeEventType.self, forKey: .type)

        switch type {
        case .pairRequest:
            self = .pairRequest(try PairRequestEvent(from: decoder))
        case .pairAccepted:
            self = .pairAccepted(try PairAcceptedEvent(from: decoder))
        case .sessionCreated:
            self = .sessionCreated(try SessionCreatedEvent(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .pairRequest(let event):
            try event.encode(to: encoder)
        case .pairAccepted(let event):
            try event.encode(to: encoder)
        case .sessionCreated(let event):
            try event.encode(to: encoder)
        }
    }
}

extension SessionEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SessionEventTypeValue.self, forKey: .type)

        switch type {
        case .createWorktree:
            self = .createWorktree(try CreateWorktreeCommand(from: decoder))
        case .fixConflicts:
            self = .fixConflicts(try FixConflictsCommand(from: decoder))
        case .executionStarted:
            self = .executionStarted(try ExecutionStartedUpdate(from: decoder))
        case .outputChunk:
            self = .outputChunk(try OutputChunkUpdate(from: decoder))
        case .executionCompleted:
            self = .executionCompleted(try ExecutionCompletedUpdate(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .createWorktree(let event):
            try event.encode(to: encoder)
        case .fixConflicts(let event):
            try event.encode(to: encoder)
        case .executionStarted(let event):
            try event.encode(to: encoder)
        case .outputChunk(let event):
            try event.encode(to: encoder)
        case .executionCompleted(let event):
            try event.encode(to: encoder)
        }
    }
}

extension UnboundEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case plane
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let plane = try container.decode(Plane.self, forKey: .plane)

        switch plane {
        case .handshake:
            self = .handshake(try HandshakeEvent(from: decoder))
        case .session:
            self = .session(try SessionEvent(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .handshake(let event):
            try event.encode(to: encoder)
        case .session(let event):
            try event.encode(to: encoder)
        }
    }
}

extension AnyEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case opcode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let opcode = try container.decode(Opcode.self, forKey: .opcode)

        switch opcode {
        case .event:
            self = .event(try UnboundEvent(from: decoder))
        case .ack:
            self = .ack(try AckFrame(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .event(let event):
            try event.encode(to: encoder)
        case .ack(let frame):
            try frame.encode(to: encoder)
        }
    }
}

// MARK: - Convenience Extensions

extension AnyEvent {
    public var eventId: String {
        switch self {
        case .event(let unboundEvent):
            return unboundEvent.eventId
        case .ack(let ackFrame):
            return ackFrame.eventId
        }
    }
}

extension UnboundEvent {
    public var eventId: String {
        switch self {
        case .handshake(let event):
            return event.eventId
        case .session(let event):
            return event.eventId
        }
    }
}

extension HandshakeEvent {
    public var eventId: String {
        switch self {
        case .pairRequest(let event):
            return event.eventId
        case .pairAccepted(let event):
            return event.eventId
        case .sessionCreated(let event):
            return event.eventId
        }
    }
}

extension SessionEvent {
    public var eventId: String {
        switch self {
        case .createWorktree(let event):
            return event.eventId
        case .fixConflicts(let event):
            return event.eventId
        case .executionStarted(let event):
            return event.eventId
        case .outputChunk(let event):
            return event.eventId
        case .executionCompleted(let event):
            return event.eventId
        }
    }

    public var sessionId: String {
        switch self {
        case .createWorktree(let event):
            return event.sessionId
        case .fixConflicts(let event):
            return event.sessionId
        case .executionStarted(let event):
            return event.sessionId
        case .outputChunk(let event):
            return event.sessionId
        case .executionCompleted(let event):
            return event.sessionId
        }
    }
}
```

## Existing Type Names to Preserve

When regenerating, these names MUST be preserved:

### Enums
- `Opcode` (cases: `event`, `ack`)
- `Plane` (cases: `handshake`, `session`)
- `SessionEventType` (cases: `remoteCommand`, `executorUpdate`)
- `HandshakeEventType` (cases: `pairRequest`, `pairAccepted`, `sessionCreated`)
- `SessionEventTypeValue` (dynamically generated from type literals)

### Payload Structs
- `PairRequestPayload`
- `PairAcceptedPayload`
- `CreateWorktreePayload`
- `FixConflictsPayload`
- `OutputChunkPayload`
- `ExecutionCompletedPayload`
- `EmptyPayload`

### Event Structs
- `PairRequestEvent`
- `PairAcceptedEvent`
- `SessionCreatedEvent`
- `CreateWorktreeCommand`
- `FixConflictsCommand`
- `ExecutionStartedUpdate`
- `OutputChunkUpdate`
- `ExecutionCompletedUpdate`
- `AckFrame`

### Union Enums
- `HandshakeEvent`
- `SessionEvent`
- `UnboundEvent`
- `AnyEvent`
