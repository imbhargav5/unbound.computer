# Schema Type Mapping

## Zod to Swift Type Mapping

| Zod Type | JSON Schema | Swift Type |
|----------|-------------|------------|
| `z.string()` | `type: "string"` | `String` |
| `z.number()` | `type: "number"` | `Double` |
| `z.boolean()` | `type: "boolean"` | `Bool` |
| `z.literal("X")` | `const: "X"` | Enum case or const property |
| `z.enum(["A", "B"])` | `enum: ["A", "B"]` | `enum: String, Codable` |
| `z.object({...})` | `type: "object"` | `struct: Codable, Equatable, Sendable` |
| `z.array(T)` | `type: "array"` | `[T]` |
| `z.optional(T)` | not in `required` | `T?` |
| `z.uuidv7()` | `format: "uuid"` | `String` |
| `z.discriminatedUnion()` | `oneOf` | `enum` with custom `Codable` |
| `z.union([A, B])` | `anyOf` | `enum` with custom `Codable` |

## Property Optionality

In Zod schemas, optionality is indicated by `.optional()`:

```typescript
// Zod
z.object({
  required: z.string(),
  optional: z.string().optional(),
})
```

In JSON Schema, optional fields are NOT in the `required` array:

```json
{
  "properties": {
    "required": { "type": "string" },
    "optional": { "type": "string" }
  },
  "required": ["required"]
}
```

In Swift, use `Optional` type:

```swift
public struct Example: Codable, Equatable, Sendable {
    public let required: String
    public let optional: String?

    public init(required: String, optional: String? = nil) {
        self.required = required
        self.optional = optional
    }
}
```

## Enum Value Mapping

### Type Discriminator Enums

| Zod Literal | Swift Enum Case | Raw Value |
|-------------|-----------------|-----------|
| `z.literal("PAIR_REQUEST")` | `.pairRequest` | `"PAIR_REQUEST"` |
| `z.literal("PAIR_ACCEPTED")` | `.pairAccepted` | `"PAIR_ACCEPTED"` |
| `z.literal("SESSION_CREATED")` | `.sessionCreated` | `"SESSION_CREATED"` |

### Session Event Type Values

| Zod Literal | Swift Enum Case | Raw Value |
|-------------|-----------------|-----------|
| `z.literal("SESSION_PAUSE_COMMAND")` | `.sessionPauseCommand` | `"SESSION_PAUSE_COMMAND"` |
| `z.literal("SESSION_RESUME_COMMAND")` | `.sessionResumeCommand` | `"SESSION_RESUME_COMMAND"` |
| `z.literal("EXECUTION_STARTED")` | `.executionStarted` | `"EXECUTION_STARTED"` |
| `z.literal("OUTPUT_CHUNK")` | `.outputChunk` | `"OUTPUT_CHUNK"` |
| `z.literal("TOOL_STARTED")` | `.toolStarted` | `"TOOL_STARTED"` |

## Struct Name Mapping

| Zod Schema Export | Swift Struct Name |
|-------------------|-------------------|
| `PairRequestEvent` | `PairRequestEvent` |
| `SessionPauseCommand` | `SessionPauseCommand` |
| `ExecutionStartedUpdate` | `ExecutionStartedUpdate` |
| `ToolStartedUpdate` | `ToolStartedUpdate` |
| `AckFrame` | `AckFrame` |

## Payload Name Mapping

| Event Schema | Payload Struct |
|--------------|----------------|
| `PairRequestEvent` | `PairRequestPayload` |
| `PairAcceptedEvent` | `PairAcceptedPayload` |
| `UserPromptCommand` | `UserPromptPayload` |
| `ToolStartedUpdate` | `ToolStartedPayload` |
| Events with `payload: z.object({})` | `EmptyPayload` (shared) |

## Discriminated Union Mapping

### Zod discriminatedUnion

```typescript
export const HandshakeEvent = z.discriminatedUnion("type", [
  PairRequestEvent,
  PairAcceptedEvent,
  SessionCreatedEvent,
]);
```

### Swift Enum

```swift
public enum HandshakeEvent: Equatable, Sendable {
    case pairRequest(PairRequestEvent)
    case pairAccepted(PairAcceptedEvent)
    case sessionCreated(SessionCreatedEvent)
}
```

### Discriminator Keys

| Union | Discriminator Key | Enum Type |
|-------|-------------------|-----------|
| `HandshakeEvent` | `type` | `HandshakeEventType` |
| `SessionEvent` | `type` | `SessionEventTypeValue` |
| `UnboundEvent` | `plane` | `Plane` |
| `AnyEvent` | `opcode` | `Opcode` |

## Nested Object Mapping

For complex nested payloads:

```typescript
// Zod
export const AttachmentSchema = z.object({
  type: z.enum(["image", "file", "url"]),
  data: z.string(),
  mimeType: z.string().optional(),
  filename: z.string().optional(),
});
```

```swift
// Swift
public struct Attachment: Codable, Equatable, Sendable {
    public let type: AttachmentType
    public let data: String
    public let mimeType: String?
    public let filename: String?

    public init(type: AttachmentType, data: String, mimeType: String? = nil, filename: String? = nil) {
        self.type = type
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
    }
}

public enum AttachmentType: String, Codable {
    case image
    case file
    case url
}
```

## Array Mapping

```typescript
// Zod
attachments: z.array(AttachmentSchema).optional()
```

```swift
// Swift
public let attachments: [Attachment]?
```
