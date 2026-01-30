# SQLite Async Refactoring Guide

This document explains the refactoring from `spawn_blocking` + `r2d2` to `tokio-rusqlite` for SQLite access.

## Summary of Changes

### 1. New Async Database Abstraction

**File**: `daemon-database/src/executor.rs`

```rust
use daemon_database::AsyncDatabase;

// Open database (spawns dedicated background thread)
let db = AsyncDatabase::open(&path).await?;

// Execute queries (runs on dedicated thread, caller awaits)
let repos = db.call(|conn| {
    queries::list_repositories(conn)
}).await?;
```

**Key characteristics**:
- Single dedicated thread for ALL SQLite operations
- Queries sent via channel (non-blocking)
- FIFO ordering guarantees
- Async callers yield, not block

### 2. Strict DB Critical Section Rule

Inside `db.call()`:

| Allowed | Forbidden |
|---------|-----------|
| SQL queries | Encryption/decryption |
| Row mapping | Mutex locking |
| Simple transforms | File I/O |
| | Network calls |
| | Heavy computation |

### 3. Handler Patterns

#### Simple Handler (DB-only)

```rust
// RepositoryList, SessionList, etc.
async fn handle_repository_list(db: &AsyncDatabase, req_id: &str) -> Response {
    let result = db.call(|conn| {
        queries::list_repositories(conn)
    }).await;

    match result {
        Ok(repos) => Response::success(req_id, serialize(repos)),
        Err(e) => Response::error(req_id, &e.to_string()),
    }
}
```

#### Complex Handler (DB + Crypto)

```rust
// MessageList: requires decryption
async fn handle_message_list(
    db: &AsyncDatabase,
    secrets: &Arc<Mutex<SecretsManager>>,
    session_id: &str,
) -> Response {
    // PHASE 1: DB FETCH (dedicated DB thread)
    let messages = db.call(move |conn| {
        queries::list_messages_for_session(conn, &session_id)
    }).await?;

    // PHASE 2: SECRET RESOLUTION (quick mutex access)
    let secret = {
        let guard = cache.lock().unwrap();
        guard.get(session_id).cloned()
    }; // Lock released immediately

    // PHASE 3: DECRYPTION (blocking pool for CPU work)
    let decrypted = tokio::task::spawn_blocking(move || {
        decrypt_all(messages, secret)
    }).await?;

    Response::success(req_id, decrypted)
}
```

## Migration Checklist

### Step 1: Update DaemonState

```rust
// Before
struct DaemonState {
    db: Arc<DatabasePool>,  // r2d2 pool
    // ...
}

// After
struct DaemonState {
    db: AsyncDatabase,  // tokio-rusqlite
    // ...
}
```

### Step 2: Update Initialization

```rust
// Before
let db = DatabasePool::open(&paths.database_file(), PoolConfig::default())?;

// After
let db = AsyncDatabase::open(&paths.database_file()).await?;
```

### Step 3: Refactor Each Handler

For each handler using `spawn_blocking`:

1. **Identify the phases**:
   - What's DB-only? → `db.call()`
   - What's secret resolution? → Quick mutex, release immediately
   - What's CPU-bound? → `spawn_blocking()`

2. **Split the code**:
   ```rust
   // Before: Everything in spawn_blocking
   let result = spawn_blocking(move || {
       let conn = db.get()?;
       let secrets = secrets.lock();
       let messages = queries::list(conn)?;
       decrypt_all(messages, secrets)  // WRONG
   }).await;

   // After: Three phases
   let messages = db.call(|conn| queries::list(conn)).await?;
   let secret = { secrets.lock().get(id).clone() };
   let decrypted = spawn_blocking(|| decrypt_all(messages, secret)).await?;
   ```

3. **Verify no forbidden operations in db.call()**

### Step 4: Update Imports

```rust
// Remove
use daemon_database::{DatabasePool, PoolConfig};

// Add
use daemon_database::AsyncDatabase;
```

## Handlers to Refactor

| Handler | Complexity | Notes |
|---------|------------|-------|
| `RepositoryList` | Simple | DB-only |
| `RepositoryCreate` | Simple | DB-only |
| `RepositoryDelete` | Simple | DB-only |
| `SessionList` | Simple | DB-only |
| `SessionGet` | Simple | DB-only |
| `SessionCreate` | Medium | DB + secret generation |
| `SessionDelete` | Simple | DB-only |
| `MessageList` | Complex | DB + secret + decrypt |
| `MessageSend` | Complex | Secret + encrypt + DB |
| `AuthStatus` | Simple | Secrets-only (no DB) |
| `AuthLogout` | Simple | Secrets-only (no DB) |
| `AuthCallback` | Medium | Secrets + device setup |

## Testing

```bash
# Run database tests
cargo test -p daemon-database

# Test specific executor tests
cargo test -p daemon-database executor
```

## Performance Impact

| Metric | Before | After |
|--------|--------|-------|
| Threads per query | 1 (from blocking pool) | 0 (task yields) |
| Pool contention | Yes (max 10 conns) | No (single thread) |
| Query ordering | Unpredictable | FIFO |
| Crypto blocking DB | Yes | No (separate phase) |
| Memory per query | ~2MB stack | ~0 (parked task) |

## Error Handling

The `AsyncDatabase` returns `DatabaseResult<T>` which includes:
- `DatabaseError::Sqlite` - rusqlite errors
- `DatabaseError::Connection` - channel/close errors
- `DatabaseError::Encryption` - crypto errors (should not happen inside db.call)

## Example: Full MessageList Refactor

See `daemon-bin/src/handlers_refactored.rs` for complete examples.
