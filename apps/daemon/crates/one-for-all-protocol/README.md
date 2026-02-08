# One For All Protocol

**Pure IPC protocol types for the Unbound daemon - no I/O, no async.** This crate defines the shared language between the IPC client (macOS app) and server (daemon). Only data types and serialization, nothing else.

## Architecture

```
┌──────────────────┐                    ┌──────────────────┐
│    macOS App      │                    │      Daemon       │
│                   │    Request         │                   │
│  Request::new()  ─┼──► JSON ────────►─┼─► Method match    │
│                   │                    │       │           │
│  Response::      ◄┼── JSON ◄─────────┼── Response::      │
│    from_json()    │    Response        │    success()      │
│                   │                    │                   │
│  Event::         ◄┼── JSON ◄─────────┼── Event::new()    │
│    from_json()    │    Stream          │                   │
└──────────────────┘                    └──────────────────┘
```

## Protocol Overview

JSON-RPC-like protocol over Unix domain sockets (NDJSON - one JSON object per line).

### Request

```rust
use one_for_all_protocol::{Request, Method};

// Auto-generates UUID v4 request ID
let req = Request::new(Method::SessionList);

// With parameters
let req = Request::with_params(
    Method::SessionCreate,
    serde_json::json!({ "title": "My Session", "repository_id": "repo-1" }),
);

// Serializes to:
// {"id":"550e8400-...","method":"session.create","params":{"title":"My Session",...}}
```

### Response

```rust
use one_for_all_protocol::{Response, error_codes};

// Success
let resp = Response::success(&req.id, serde_json::json!({ "id": "sess-1" }));

// Error
let resp = Response::error(&req.id, error_codes::NOT_FOUND, "Session not found");

// Check
resp.is_success(); // true or false
```

### Event (Streaming)

```rust
use one_for_all_protocol::{Event, EventType};

let event = Event::new(
    EventType::Message,
    "session-123".to_string(),
    serde_json::json!({ "content": "Hello" }),
    42, // sequence number
);
```

## Methods (35 total)

### Health & Lifecycle

| Method | Wire Name |
|--------|-----------|
| `Health` | `health` |
| `Shutdown` | `shutdown` |

### Authentication

| Method | Wire Name |
|--------|-----------|
| `AuthStatus` | `auth.status` |
| `AuthLogin` | `auth.login` |
| `AuthLogout` | `auth.logout` |

### Sessions

| Method | Wire Name |
|--------|-----------|
| `SessionList` | `session.list` |
| `SessionCreate` | `session.create` |
| `SessionGet` | `session.get` |
| `SessionDelete` | `session.delete` |
| `SessionSubscribe` | `session.subscribe` |
| `SessionUnsubscribe` | `session.unsubscribe` |

### Messages

| Method | Wire Name |
|--------|-----------|
| `MessageList` | `message.list` |
| `MessageSend` | `message.send` |

### Outbox

| Method | Wire Name |
|--------|-----------|
| `OutboxStatus` | `outbox.status` |

### Repositories

| Method | Wire Name |
|--------|-----------|
| `RepositoryList` | `repository.list` |
| `RepositoryAdd` | `repository.add` |
| `RepositoryRemove` | `repository.remove` |
| `RepositoryListFiles` | `repository.list_files` |
| `RepositoryReadFile` | `repository.read_file` |
| `RepositoryReadFileSlice` | `repository.read_file_slice` |
| `RepositoryWriteFile` | `repository.write_file` |
| `RepositoryReplaceFileRange` | `repository.replace_file_range` |

### Claude CLI

| Method | Wire Name |
|--------|-----------|
| `ClaudeSend` | `claude.send` |
| `ClaudeStatus` | `claude.status` |
| `ClaudeStop` | `claude.stop` |

### Git

| Method | Wire Name |
|--------|-----------|
| `GitStatus` | `git.status` |
| `GitDiffFile` | `git.diff_file` |
| `GitLog` | `git.log` |
| `GitBranches` | `git.branches` |
| `GitStage` | `git.stage` |
| `GitUnstage` | `git.unstage` |
| `GitDiscard` | `git.discard` |

### Terminal

| Method | Wire Name |
|--------|-----------|
| `TerminalRun` | `terminal.run` |
| `TerminalStatus` | `terminal.status` |
| `TerminalStop` | `terminal.stop` |

## Event Types

| EventType | Description |
|-----------|-------------|
| `Message` | New message added to session |
| `StreamingChunk` | Real-time Claude response chunk |
| `StatusChange` | Session status changed |
| `InitialState` | State dump on subscribe |
| `Ping` | Keepalive |
| `TerminalOutput` | Terminal stdout/stderr |
| `TerminalFinished` | Terminal process exited |
| `ClaudeEvent` | Raw Claude NDJSON event |
| `AuthStateChanged` | Login/logout state change |
| `SessionCreated` | New session created |
| `SessionDeleted` | Session removed |

## Error Codes

Standard JSON-RPC codes plus custom extensions:

```rust
pub mod error_codes {
    // Standard JSON-RPC
    pub const PARSE_ERROR: i32 = -32700;
    pub const INVALID_REQUEST: i32 = -32600;
    pub const METHOD_NOT_FOUND: i32 = -32601;
    pub const INVALID_PARAMS: i32 = -32602;
    pub const INTERNAL_ERROR: i32 = -32603;

    // Custom
    pub const NOT_AUTHENTICATED: i32 = -32001;
    pub const NOT_FOUND: i32 = -32002;
    pub const CONFLICT: i32 = -32003;
}
```

## Design Principles

- **Zero dependencies on I/O or async** - Pure data types and serde
- **UUID v4 correlation** - Every request auto-generates an ID for response matching
- **Exclusive result/error** - Responses carry either `result` or `error`, never both
- **Sequence numbers** - Events are ordered for resumption after reconnect
- **Wire-format stability** - Method names use `serde(rename)` for stable JSON keys

## Testing

```bash
cargo test -p one-for-all-protocol
```

50+ tests covering serialization round-trips, method name mapping, error construction, event formatting, and edge cases.
