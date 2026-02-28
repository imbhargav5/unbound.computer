# Armin

A SQLite-backed session engine that commits facts, derives fast read views, and emits side-effects.

## Non-negotiable Principles

Put these at the top of your mental model:

1. **SQLite is the only durable store** - Every write commits to SQLite first
2. **Snapshots, deltas, live streams are derived** - Reads never cause side-effects
3. **Side-effects reflect committed reality** - Emitted after SQLite commit
4. **Recovery emits nothing** - Crash = rebuild from SQLite
5. **Performance is achieved via derivation, not mutation**

## Mental Model

```
WRITE:
  SQLite → derived state → side-effect

READ:
  snapshot + delta + live

CRASH:
  SQLite → rebuild → continue
```

Or simply:

> **Armin commits reality, then announces it.**

## Quick Start

```rust
use agent_session_sqlite_persist_core::{Armin, NewMessage, Role, SessionReader, SessionWriter};
use agent_session_sqlite_persist_core::side_effect::RecordingSink;

// Create an in-memory engine for testing
let sink = RecordingSink::new();
let engine = Armin::in_memory(sink).unwrap();

// Create a session
let session_id = engine.create_session();

// Append messages
engine.append(session_id, NewMessage {
    role: Role::User,
    content: "Hello!".to_string(),
});

// Read via delta
let delta = engine.delta(session_id);
assert_eq!(delta.len(), 1);

// Subscribe to live updates
let subscription = engine.subscribe(session_id);

// Append another message
engine.append(session_id, NewMessage {
    role: Role::Assistant,
    content: "Hi there!".to_string(),
});

// Receive via subscription
let msg = subscription.try_recv().unwrap();
assert_eq!(msg.content, "Hi there!");
```

## Architecture

### Write Path (strict order)

1. **Commit fact** to SQLite
2. **Update derived state** (delta, live)
3. **Emit side-effect**

If step 1 fails → nothing else runs.
Side-effects always observe committed state.

### Read Path (pure, fast)

- **Snapshot**: Immutable view of all sessions at a point in time
- **Delta**: Messages appended since the last snapshot
- **Live**: Real-time subscription to new messages

Reads never hit SQLite directly (except on recovery).
Reads never emit side-effects.

### Recovery (silent)

On startup:
1. Open SQLite
2. Load sessions
3. Rebuild deltas
4. Serve reads

Rules:
- No side-effects
- No live notifications
- No replay

## Crate Structure

```
agent-session-sqlite-persist-core/
├── Cargo.toml
├── README.md
├── ARCHITECTURE.md
└── src/
    ├── lib.rs                // public API
    ├── armin.rs              // Armin engine (brain)
    ├── reader.rs             // read-side traits
    ├── writer.rs             // write-side traits
    ├── side_effect.rs        // side-effect contracts
    ├── sqlite.rs             // SQLite access (ONLY store)
    ├── snapshot.rs           // immutable snapshot views
    ├── delta.rs              // append-only deltas
    ├── live.rs               // live subscriptions
    ├── types.rs              // core types
    └── tests/
        ├── mod.rs
        ├── side_effects.rs
        ├── recovery.rs
        └── invariants.rs
```

## Side Effects

Side-effects are opaque and testable:

```rust
use agent_session_sqlite_persist_core::side_effect::{SideEffect, SideEffectSink, RecordingSink};

// Armin emits
// Sink decides what it means
// Tests assert emission, not behavior

let sink = RecordingSink::new();
let engine = Armin::in_memory(sink).unwrap();

engine.create_session();

assert_eq!(
    engine.sink().effects(),
    vec![SideEffect::SessionCreated { session_id: SessionId(1) }]
);
```

Available side-effects:
- `RepositoryCreated { repository_id }`
- `RepositoryDeleted { repository_id }`
- `SessionCreated { session_id }`
- `SessionClosed { session_id }`
- `SessionDeleted { session_id }`
- `SessionUpdated { session_id }`
- `MessageAppended { session_id, message_id, sequence_number, content }`
- `RuntimeStatusUpdated { session_id, runtime_status }`

## What Armin Deliberately Does NOT Do

- ❌ No networking
- ❌ No retries
- ❌ No async
- ❌ No storage abstraction
- ❌ No distributed guarantees

Those live above Armin.

## SQLite Schema

```sql
sessions(
  id INTEGER PRIMARY KEY,
  closed INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

messages(
  id INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL,
  role INTEGER NOT NULL,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
```

SQLite guarantees:
- Atomic commits
- Total ordering
- Recovery

## Testing

Use in-memory SQLite and `RecordingSink`:

```rust
#[test]
fn emits_side_effect_after_commit() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session_id = armin.create_session();
    armin.append(session_id, NewMessage {
        role: Role::User,
        content: "Hello".to_string(),
    });

    assert_eq!(armin.sink().len(), 2); // SessionCreated + MessageAppended
}
```

You can test:
- Ordering
- Presence
- Absence
- Recovery silence

## License

MIT
