# Armin Architecture

This document describes the internal architecture of the Armin session engine.

## Core Principles

### SQLite is the Only Source of Truth

Every piece of durable state lives in SQLite. There are no alternative backends, no pluggable storage engines, no in-memory modes for production.

```
┌─────────────────────────────────────────────────────────────┐
│                        Armin Engine                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐                  │
│  │Snapshot │    │ Delta   │    │  Live   │   Derived State  │
│  │  View   │    │ Store   │    │   Hub   │   (in-memory)    │
│  └────┬────┘    └────┬────┘    └────┬────┘                  │
│       │              │              │                        │
│       └──────────────┼──────────────┘                        │
│                      │                                       │
│                      ▼                                       │
│            ┌─────────────────┐                               │
│            │   SQLiteStore   │  Source of Truth              │
│            │   (durability)  │  (the ONLY one)               │
│            └────────┬────────┘                               │
│                     │                                        │
└─────────────────────┼────────────────────────────────────────┘
                      │
                      ▼
              ┌───────────────┐
              │  SQLite DB    │
              │  (on disk)    │
              └───────────────┘
```

### Write Path: Commit First, Derive Second, Emit Third

Every write follows a strict, non-negotiable order:

```
1. Commit fact to SQLite     ← If this fails, STOP
         │
         ▼
2. Update derived state      ← Delta, Live Hub
         │
         ▼
3. Emit side-effect          ← Always reflects committed reality
```

This ordering guarantees:
- Side-effects never observe uncommitted state
- Crash at any point leaves SQLite consistent
- Recovery can rebuild derived state from SQLite

### Read Path: Pure and Fast

Reads are separated from writes and optimized for speed:

```
         ┌─────────────────────────────────────┐
         │           Read Request               │
         └────────────────┬────────────────────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
    ┌─────────┐     ┌─────────┐     ┌─────────┐
    │Snapshot │     │ Delta   │     │  Live   │
    │ (past)  │     │(recent) │     │(future) │
    └─────────┘     └─────────┘     └─────────┘
```

- **Snapshot**: Immutable view at a point in time
- **Delta**: Changes since the snapshot
- **Live**: Subscription for future changes

Reads NEVER:
- Hit SQLite directly (except recovery)
- Cause side-effects
- Block writers

## Component Details

### SqliteStore

The central and ONLY durable store.

```rust
pub struct SqliteStore {
    conn: rusqlite::Connection,
}
```

Responsibilities:
- Schema management
- ACID transactions
- Ordering guarantees
- Crash recovery

Schema:
```sql
sessions(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  closed INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

messages(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL,
  role INTEGER NOT NULL,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (session_id) REFERENCES sessions(id)
);
```

### SnapshotView

Immutable view of all sessions at a point in time.

```rust
pub struct SnapshotView {
    sessions: Arc<HashMap<SessionId, SessionSnapshot>>,
}
```

- Created during recovery
- Refreshed on demand via `refresh_snapshot()`
- Cheap to clone (Arc)
- Never mutated after creation

### DeltaStore

Tracks messages appended since the last snapshot.

```rust
pub struct DeltaStore {
    deltas: RwLock<HashMap<SessionId, SessionDelta>>,
}
```

- Append-only during normal operation
- Cleared when snapshot is refreshed
- Thread-safe (RwLock)

### LiveHub

Manages real-time subscriptions.

```rust
pub struct LiveHub {
    subscribers: RwLock<HashMap<SessionId, Vec<Sender<Message>>>>,
}
```

- Channel-based pub/sub
- Automatic cleanup of dead subscribers
- No replay of historical messages

### SideEffectSink

Trait for receiving side-effects.

```rust
pub trait SideEffectSink: Send + Sync {
    fn emit(&self, effect: SideEffect);
}
```

Built-in implementations:
- `NullSink`: Discards all effects (for recovery)
- `RecordingSink`: Records for testing

## Recovery Process

On startup, Armin performs silent recovery:

```
┌───────────────────────────────────────────────────────────┐
│                    RECOVERY PROCESS                        │
├───────────────────────────────────────────────────────────┤
│                                                            │
│  1. Open SQLite                                            │
│         │                                                  │
│         ▼                                                  │
│  2. List all sessions                                      │
│         │                                                  │
│         ▼                                                  │
│  3. For each session:                                      │
│     a. Load messages from SQLite                           │
│     b. Create SessionSnapshot                              │
│     c. Initialize delta cursor                             │
│         │                                                  │
│         ▼                                                  │
│  4. Build SnapshotView                                     │
│         │                                                  │
│         ▼                                                  │
│  5. Ready to serve                                         │
│                                                            │
│  ⚠️  NO side-effects emitted                               │
│  ⚠️  NO live notifications sent                            │
│                                                            │
└───────────────────────────────────────────────────────────┘
```

## Thread Safety

Armin is designed for single-threaded use with the engine, but:

- `DeltaStore`: RwLock for concurrent reads
- `LiveHub`: RwLock for subscription management
- `RecordingSink`: Mutex for effect collection
- `SnapshotView`: Arc for cheap cloning

The engine itself (`Armin<S>`) is not `Sync` because `rusqlite::Connection` is not thread-safe. For multi-threaded access, wrap in a mutex or use connection pooling.

## Error Handling

Errors are minimal and focused:

```rust
pub enum ArminError {
    Sqlite(rusqlite::Error),
}
```

Philosophy:
- Let SQLite handle data integrity
- Panic on invariant violations (e.g., append to closed session)
- Return errors for recoverable failures (e.g., connection issues)

## Testing Strategy

### Unit Tests

Each module has its own tests:
- `types.rs`: Type conversions, equality
- `sqlite.rs`: CRUD operations
- `snapshot.rs`: View construction
- `delta.rs`: Append and iteration
- `live.rs`: Subscription delivery

### Integration Tests

In `tests/` directory:
- `side_effects.rs`: Emission ordering, presence, absence
- `recovery.rs`: State rebuild, silence guarantees
- `invariants.rs`: Ordering, consistency, isolation

### Test Utilities

```rust
// In-memory database
let store = SqliteStore::in_memory().unwrap();

// Recording sink
let sink = RecordingSink::new();
assert_eq!(sink.effects(), vec![...]);

// Temporary file database
let temp_file = NamedTempFile::new().unwrap();
let armin = Armin::open(temp_file.path(), sink).unwrap();
```

## Performance Considerations

1. **Snapshot Refresh**: Rebuilds entire snapshot from SQLite. Do sparingly.

2. **Delta Size**: Deltas grow unbounded until snapshot refresh. Consider periodic refresh for long-running sessions.

3. **Live Subscribers**: Cleaned up lazily on next notify. Many dead subscribers = wasted send attempts.

4. **SQLite**: Uses AUTOINCREMENT for ordering guarantees. Creates indexes on `session_id` for query performance.

## What's NOT in Armin

By design, Armin does not include:

| Feature | Reason |
|---------|--------|
| Networking | Lives in transport layer |
| Retries | Lives in coordination layer |
| Async | Simplicity, SQLite is sync |
| Storage abstraction | SQLite is THE store |
| Distributed guarantees | Single-node only |
| Compaction | Manual snapshot refresh |
| TTL/Expiration | Application concern |

These features belong in layers above Armin.
