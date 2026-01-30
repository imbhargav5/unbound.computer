# Swift Code Patterns

## Basic Enum with Raw String Value

```swift
public enum Opcode: String, Codable {
    case event = "EVENT"
    case ack = "ACK"
}
```

## Payload Struct

```swift
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
```

## Empty Payload

```swift
public struct EmptyPayload: Codable, Equatable, Sendable {
    public init() {}
}
```

## Payload with Optional Fields

```swift
public struct SessionStopPayload: Codable, Equatable, Sendable {
    public let force: Bool?

    public init(force: Bool? = nil) {
        self.force = force
    }
}
```

## Concrete Event Type

```swift
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
```

## AckFrame (Simple Type)

```swift
public struct AckFrame: Codable, Equatable, Sendable {
    public let opcode: Opcode
    public let eventId: String

    public init(eventId: String) {
        self.opcode = .ack
        self.eventId = eventId
    }
}
```

## Discriminated Union Enum

```swift
public enum HandshakeEvent: Equatable, Sendable {
    case pairRequest(PairRequestEvent)
    case pairAccepted(PairAcceptedEvent)
    case sessionCreated(SessionCreatedEvent)
}
```

## Codable Extension for Discriminated Union

```swift
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
```

## Nested Union (UnboundEvent)

```swift
public enum UnboundEvent: Equatable, Sendable {
    case handshake(HandshakeEvent)
    case session(SessionEvent)
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
```

## Top-Level Union (AnyEvent)

```swift
public enum AnyEvent: Equatable, Sendable {
    case event(UnboundEvent)
    case ack(AckFrame)
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
```

## Convenience Extension for eventId

```swift
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
```

## Session Event Convenience Extensions

```swift
extension SessionEvent {
    public var eventId: String {
        switch self {
        case .sessionPause(let event):
            return event.eventId
        // ... all cases
        }
    }

    public var sessionId: String {
        switch self {
        case .sessionPause(let event):
            return event.sessionId
        // ... all cases
        }
    }
}
```

## Enum Case Naming Convention

Convert `SCREAMING_SNAKE_CASE` to `camelCase`:
- `PAIR_REQUEST` → `.pairRequest`
- `SESSION_PAUSE_COMMAND` → `.sessionPauseCommand`
- `EXECUTION_STARTED` → `.executionStarted`

## Struct Naming Convention

Convert type literal to PascalCase struct:
- `"SESSION_PAUSE_COMMAND"` → `SessionPauseCommand`
- `"EXECUTION_STARTED"` → `ExecutionStartedUpdate`
- `"TOOL_STARTED"` → `ToolStartedUpdate`
