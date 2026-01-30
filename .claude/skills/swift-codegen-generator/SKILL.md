# Swift Code Generator for Transport Reliability

Generate strongly-typed Swift code from Zod schemas for the transport-reliability package.

## When to Use This Skill

- Regenerating `TransportReliability.swift` after schema changes
- Adding new event types to the transport protocol
- Updating existing event payload structures
- Ensuring Swift types stay in sync with TypeScript schemas

## Input Files

**Zod Schemas** (source of truth):
- `packages/transport-reliability/src/schemas/ack.ts`
- `packages/transport-reliability/src/schemas/base.ts`
- `packages/transport-reliability/src/schemas/handshake-events.ts`
- `packages/transport-reliability/src/schemas/session-events.ts`
- `packages/transport-reliability/src/schemas/any-event.ts`

**JSON Schemas** (for reference):
- `packages/transport-reliability/generated/json-schemas/*.json`

**Existing Swift File** (for name preservation):
- `packages/transport-reliability/generated/TransportReliability.swift`

## Output File

- `packages/transport-reliability/generated/TransportReliability.swift`

## Generation Process

### Step 1: Read Existing Swift File
ALWAYS read `TransportReliability.swift` first to:
- Identify existing type names to preserve
- Understand current code structure
- Avoid breaking changes to dependent code

### Step 2: Read All Zod Schemas
Read all schema files in order:
1. `base.ts` - Base event structure
2. `ack.ts` - ACK frame
3. `handshake-events.ts` - Handshake protocol events
4. `session-events.ts` - All session commands and updates
5. `any-event.ts` - Union types

### Step 3: Generate Swift Code

Generate in this order:

```
// MARK: - Enums (from z.enum() and z.literal() values)
// MARK: - Payload Types (from payload objects)
// MARK: - Concrete Event Types (from each event schema)
// MARK: - Discriminated Unions (from z.discriminatedUnion())
// MARK: - Codable Extensions (custom encoding/decoding)
// MARK: - Convenience Extensions (helper properties)
```

## Critical Rules

### 1. Name Preservation
- **MUST** preserve existing Swift type names
- If a struct exists as `PairRequestEvent`, keep it as `PairRequestEvent`
- Never rename existing types as it breaks dependent code

### 2. Naming Conventions
| Zod Pattern | Swift Pattern | Example |
|-------------|---------------|---------|
| `SCREAMING_SNAKE_CASE` type literal | PascalCase struct | `SESSION_PAUSE_COMMAND` → `SessionPauseCommand` |
| `SCREAMING_SNAKE_CASE` enum value | camelCase enum case | `PAIR_REQUEST` → `.pairRequest` |
| `camelCase` property | camelCase property | `eventId` → `eventId` |
| Payload object | `{EventName}Payload` struct | `PairRequestPayload` |
| Empty payload | `EmptyPayload` | Shared across events |

### 3. Type Conformance
All generated types MUST conform to:
- `Codable` - JSON serialization
- `Equatable` - Value comparison
- `Sendable` - Thread safety

### 4. Struct Requirements
Every struct must have:
- `public` access modifier on type and all members
- Explicit `public init()` with all parameters
- Properties declared with `let` (immutable)

### 5. Discriminated Union Pattern
For `z.discriminatedUnion()`, generate:
- Swift `enum` with associated values
- Custom `Codable` extension using discriminator key
- Switch over discriminator to decode correct type

## Type Mapping

See `references/schema-mapping.md` for complete type mapping table.

## Swift Patterns

See `references/patterns.md` for code patterns and templates.

## Example Output

See `references/example-output.md` for reference Swift code.

## File Header

Always include this header:
```swift
// This file was generated from Zod schemas, do not modify it directly.
// Run `/swift-codegen-generator` to regenerate.

import Foundation
```

## Validation Checklist

Before outputting, verify:
- [ ] All existing type names preserved
- [ ] All Zod schemas represented
- [ ] Discriminated unions have custom Codable
- [ ] All structs have public init
- [ ] All types conform to Codable, Equatable, Sendable
- [ ] eventId convenience extensions present
- [ ] No hardcoded values that should be dynamic
