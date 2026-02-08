# Daemon Architecture Review: Subcrate Extraction Plan

## Executive Summary

The daemon currently has 15 crates, but `daemon-bin` has become a monolith that absorbs business logic that should live in testable library crates. The handlers in `daemon-bin` contain orchestration logic (process lifecycle, session creation with encryption + worktree + Supabase sync, secret loading) that can't be tested without spinning up the full daemon. Meanwhile, `daemon-ipc` conflates transport mechanics with protocol definitions.

This review proposes extracting **6 new named crates** from `daemon-bin` and splitting `daemon-ipc` into two crates, following the existing naming convention (Armin, Falco, Deku, etc.).

---

## Current Problems

### 1. DaemonState is a God Object (17 fields)

Every handler receives the entire `DaemonState` via clone. This means:

- **No compile-time enforcement** of which handler uses which dependency
- **Every handler test** would need to construct the full 17-field struct
- **Adding a field** forces recompilation of every handler

```
state.rs:20-58 — DaemonState has fields for:
  config, paths, db, secrets, claude_processes, terminal_processes,
  db_encryption_key, subscriptions, session_secret_cache, supabase_client,
  device_id, device_private_key, session_sync, toshinori, message_sync,
  armin, gyomei
```

### 2. Business Logic Lives in IPC Handlers

The handlers in `daemon-bin/src/ipc/handlers/` aren't thin adapters — they contain domain logic:

| Handler | Lines | Logic that should be in a library |
|---------|-------|----------------------------------|
| `claude.rs` | 300 | Process spawning, session resume, working dir resolution, event stream wiring |
| `session.rs` | 407 | Worktree creation, secret generation + encryption + cache + Supabase sync |
| `terminal.rs` | 231 | Process spawning, stdout/stderr capture, stop signal wiring |
| `repository.rs` | 806 | Path resolution, file R/W orchestration with conflict detection |
| `git.rs` | 410 | Path resolution + delegation (thin, but repeated pattern) |

The handlers also contain ANSI color codes in log messages (`\x1b[36m[CLAUDE]\x1b[0m`) which bypasses the structured logging system.

### 3. machines/ Contains Untestable Orchestration

`machines/claude/stream.rs` and `machines/terminal/stream.rs` bridge external process events to Armin + IPC subscriptions. This is core business logic — _how_ Claude events become stored messages and broadcast events — but it takes `DaemonState` as input and spawns `tokio::spawn` tasks internally, making it impossible to test without a running daemon.

### 4. daemon-ipc Mixes Transport and Protocol

`daemon-ipc` currently contains:
- **Protocol definitions** (Method enum, Request/Response types, Event/EventType, error codes)
- **Transport implementation** (IpcServer, IpcClient, Unix socket handling, subscription broadcasting)

The CLI (`cli-new`) depends on `daemon-ipc` to get the protocol types, but this forces it to also compile the server code it never uses.

### 5. Secret Management Logic is in utils/

`utils/secrets.rs` and `utils/session_secret_cache.rs` contain the 3-tier secret cache (memory → SQLite → keychain) and Supabase secret loading. This is reusable domain logic trapped in a binary crate.

### 6. Test Coverage Gaps

| Crate | Tests | Assessment |
|-------|-------|-----------|
| armin | 190 | Excellent — 120 documented rules |
| piccolo | 97 | Good — real integration tests |
| daemon-auth | 51 | Good — FSM coverage |
| **daemon-bin** | **3** | **Almost zero coverage for 2000+ lines of business logic** |
| daemon-ipc | 15 | Protocol only — no server/client integration tests |
| toshinori | 2 | Stub-level |

The handlers, machines, and secret management in `daemon-bin` have effectively **zero test coverage** because the code is structured in a way that makes unit testing impractical.

---

## Proposed New Crates

### Crate 1: `rengoku-sessions` — Session Orchestrator

**Extracted from:** `daemon-bin/src/ipc/handlers/session.rs`, `daemon-bin/src/utils/session_secret_cache.rs`

**Responsibility:** Session lifecycle management — creation (with optional worktree), deletion (with worktree cleanup), secret generation/encryption/caching, and Supabase sync coordination.

```
rengoku-sessions/
├── src/
│   ├── lib.rs
│   ├── create.rs        # Session creation: ID gen → worktree → Armin → encrypt secret → cache → sync
│   ├── delete.rs        # Session deletion: worktree cleanup → Armin delete
│   ├── secret_cache.rs  # 3-tier cache: memory → SQLite → keychain
│   └── secret_loader.rs # Load secrets from Supabase at startup
```

**Dependencies:** `armin`, `piccolo`, `daemon-database`, `daemon-storage`, `daemon-config-and-utils`

**What daemon-bin keeps:** Thin IPC handlers that parse params → call `rengoku_sessions::create_session(...)` → serialize response.

**Testability gains:**
- Test session creation without IPC server
- Test secret cache tiers independently
- Test worktree creation + session creation as a transaction
- Mock Armin/piccolo/database independently via traits

**Example API:**

```rust
pub struct SessionOrchestrator<A: SessionWriter + SessionReader, S: SecretStore> {
    armin: A,
    secret_cache: SessionSecretCache,
    secret_store: S,
}

impl<A, S> SessionOrchestrator<A, S> {
    pub fn create(&self, params: CreateSessionParams) -> Result<CreatedSession, SessionError>;
    pub fn delete(&self, session_id: &SessionId) -> Result<bool, SessionError>;
}
```

---

### Crate 2: `eren-machines` — Process Orchestrator

**Extracted from:** `daemon-bin/src/ipc/handlers/claude.rs`, `daemon-bin/src/machines/claude/stream.rs`, `daemon-bin/src/ipc/handlers/terminal.rs`, `daemon-bin/src/machines/terminal/stream.rs`

**Responsibility:** Process lifecycle for Claude CLI and terminal commands — spawning, event stream processing, status tracking, and graceful shutdown.

```
eren-machines/
├── src/
│   ├── lib.rs
│   ├── claude.rs          # Claude process: spawn → stream events → store messages → cleanup
│   ├── terminal.rs        # Terminal process: spawn → capture output → store messages → cleanup
│   ├── process_registry.rs # Track running processes by session_id
│   ├── event_bridge.rs    # Bridge process events → Armin messages + broadcast events
│   └── types.rs           # ProcessStatus, ProcessHandle, etc.
```

**Dependencies:** `armin`, `deku`

**What daemon-bin keeps:** IPC handlers that parse params → call `eren_machines::spawn_claude(...)` → serialize response. No more `tokio::spawn` in handlers.

**Testability gains:**
- Test Claude event → Armin message mapping without a real Claude process
- Test process registry (start/stop/status) as pure state machine
- Test terminal output capture with mock child process
- Integration test: mock `ClaudeEventStream` → verify stored messages

**Example API:**

```rust
pub struct ProcessManager<W: SessionWriter> {
    writer: W,
    claude_processes: ProcessRegistry,
    terminal_processes: ProcessRegistry,
}

impl<W: SessionWriter> ProcessManager<W> {
    pub async fn spawn_claude(&self, params: ClaudeSpawnParams) -> Result<ProcessHandle, ProcessError>;
    pub async fn spawn_terminal(&self, params: TerminalSpawnParams) -> Result<ProcessHandle, ProcessError>;
    pub fn status(&self, session_id: &str) -> ProcessStatus;
    pub fn stop(&self, session_id: &str) -> bool;
}
```

---

### Crate 3: `sakura-working-dir-resolution` — Workspace Resolver

**Extracted from:** `daemon-bin/src/ipc/handlers/repository.rs` (path resolution logic), `daemon-bin/src/ipc/handlers/claude.rs` (working dir resolution)

**Responsibility:** Resolve the correct working directory for a session (worktree path vs. repository path) and validate paths for file operations.

```
sakura-working-dir-resolution/
├── src/
│   ├── lib.rs
│   ├── resolver.rs     # Session → working directory resolution
│   ├── file_ops.rs     # Orchestrate gyomei read/write with path validation
│   └── directory.rs    # Orchestrate yagami listing with path validation
```

**Dependencies:** `armin`, `gyomei`, `yagami`

**Rationale:** The "resolve session to working directory" pattern is duplicated across `claude.rs`, `terminal.rs`, `repository.rs`, and `git.rs`. Each reimplements the same lookup chain: `session_id → session.worktree_path || repo.path`. Extracting this eliminates duplication and makes the resolution logic testable.

**Testability gains:**
- Test path resolution with mock Armin (no database)
- Test that worktree paths take precedence over repo paths
- Test path traversal prevention in isolation

---

### Crate 4: `one-for-all-protocol` — Protocol Definitions

**Extracted from:** `daemon-ipc/src/protocol.rs`, `daemon-ipc/src/error.rs`

**Responsibility:** Pure data types for the IPC protocol — no I/O, no async, no transport.

```
one-for-all-protocol/
├── src/
│   ├── lib.rs
│   ├── method.rs       # Method enum (Health, SessionCreate, ClaudeSend, etc.)
│   ├── request.rs      # Request { id, method, params }
│   ├── response.rs     # Response { id, result, error }
│   ├── event.rs        # Event { event_type, session_id, data, sequence }
│   ├── event_type.rs   # EventType enum
│   └── error_codes.rs  # JSON-RPC error code constants
```

**Dependencies:** `serde`, `serde_json`, `uuid` — no async runtime, no I/O

**What daemon-ipc keeps:** `IpcServer`, `IpcClient`, `SubscriptionManager`, `StreamingSubscription` — the transport layer that uses `one-for-all-protocol` types.

**Rationale:** The CLI crate currently depends on `daemon-ipc` just to use `Method`, `Request`, and `Response`. With `one-for-all-protocol`, the CLI depends only on the lightweight protocol types. `daemon-ipc` becomes a pure transport crate that depends on `one-for-all-protocol`.

**Testability gains:**
- Protocol serialization tests don't need async runtime
- Client and server can be tested against protocol types without coupling
- New transports (WebSocket, HTTP) can be built on `one-for-all-protocol` types

---

### Crate 5: `sasuke-crypto` — Device Identity & Crypto Coordinator

**Extracted from:** `daemon-bin/src/app/init.rs` (crypto material loading), `daemon-bin/src/utils/secrets.rs` (Supabase secret loading)

**Responsibility:** Device identity management — loading device ID/private key from keychain, deriving database encryption key, loading session secrets from Supabase.

```
sasuke-crypto/
├── src/
│   ├── lib.rs
│   ├── identity.rs       # Load/cache device_id and device_private_key
│   ├── encryption_key.rs # Derive and cache db_encryption_key from device private key
│   └── remote_secrets.rs # Fetch and decrypt session secrets from Supabase
```

**Dependencies:** `daemon-config-and-utils`, `daemon-storage`, `daemon-auth` (SupabaseClient)

**Rationale:** The init.rs file has 15 lines of crypto material loading interleaved with service initialization. This logic silently swallows errors (`Ok(None)` when no key found) and is untestable in its current form. Extracting it allows testing key derivation, error handling, and Supabase secret loading independently.

**Testability gains:**
- Test that missing device key is handled correctly
- Test Supabase secret decryption with known test vectors
- Test key derivation without keychain access (mock SecretsManager)

---

### Crate 6: `historia-lifecycle` — Daemon Lifecycle

**Extracted from:** `daemon-bin/src/app/init.rs`, `daemon-bin/src/app/lifecycle.rs`

**Responsibility:** Daemon startup orchestration, singleton enforcement, graceful shutdown, and PID file management.

```
historia-lifecycle/
├── src/
│   ├── lib.rs
│   ├── singleton.rs    # Check if daemon already running, clean stale sockets
│   ├── startup.rs      # Service initialization ordering and dependency wiring
│   ├── shutdown.rs     # Graceful shutdown coordination
│   └── pidfile.rs      # PID file write/cleanup
```

**Dependencies:** `daemon-ipc`, `daemon-config-and-utils`

**Rationale:** Startup and shutdown logic is currently mixed with service construction in `init.rs`. Extracting it makes the lifecycle testable (can we detect a stale socket? does shutdown clean up PID files?) and clarifies the initialization order.

**Testability gains:**
- Test singleton detection with mock socket
- Test PID file lifecycle
- Test shutdown signal propagation
- Test that startup fails correctly when required services are unavailable

---

## Resulting Architecture

### Before

```
daemon-bin (2000+ lines of business logic, 3 tests)
├── app/init.rs          — monolithic startup
├── app/state.rs         — god object (17 fields)
├── ipc/handlers/*.rs    — business logic in IPC layer
├── machines/*.rs        — untestable event bridges
├── utils/*.rs           — reusable logic trapped in binary
└── armin_adapter.rs     — well-designed (keep as-is)
```

### After

```
daemon-bin (thin shell: CLI, handler registration, state wiring)
├── main.rs              — CLI parsing, delegates to historia-lifecycle
├── ipc/handlers/*.rs    — parameter extraction + delegation only (< 30 lines each)
└── armin_adapter.rs     — keep as-is

one-for-all-protocol  — protocol types (Method, Request, Response, Event)
daemon-ipc            — transport (IpcServer, IpcClient) using one-for-all-protocol types
rengoku-sessions      — session lifecycle (create, delete, secrets)
eren-machines         — process management (Claude, terminal)
sakura-working-dir-resolution — workspace resolution (session → working dir)
sasuke-crypto         — device identity & crypto coordination
historia-lifecycle    — daemon lifecycle (startup, shutdown, singleton)
```

### Dependency Graph

```
              one-for-all-protocol (protocol types)
                   /              \
          daemon-ipc              cli-new
         (transport)
              |
          daemon-bin (thin shell)
         /    |    \               \
  rengoku  eren   sakura     historia
 -sessions -machines -working   -lifecycle
    |         |     -dir-res.      |
    +---------+---------+----------+
    |                              |
  armin                     sasuke-crypto
    |                              |
daemon-database             daemon-storage
                                   |
                              daemon-config-and-utils
```

### DaemonState After Refactoring

```rust
pub struct DaemonState {
    // Infrastructure
    pub config: Arc<Config>,
    pub paths: Arc<Paths>,
    pub subscriptions: SubscriptionManager,

    // Domain services (each owns its own dependencies)
    pub sessions: Arc<rengoku_sessions::SessionOrchestrator>,
    pub processes: Arc<eren_machines::ProcessManager>,
    pub workspace: Arc<sakura_working_dir_resolution::WorkspaceResolver>,
    pub identity: Arc<sasuke_crypto::DeviceIdentity>,

    // Core engines (shared by domain services)
    pub armin: Arc<DaemonArmin>,
    pub gyomei: Arc<Gyomei>,
}
```

From 17 fields to 9, with clear ownership boundaries.

---

## Migration Strategy

### Phase 1: Extract protocol types (low risk, high value)

1. Create `one-for-all-protocol` from `daemon-ipc/src/protocol.rs` + `error.rs`
2. Make `daemon-ipc` depend on `one-for-all-protocol` and re-export types
3. Update `cli-new` to depend on `one-for-all-protocol` directly
4. **Zero breaking changes** — re-exports maintain compatibility

### Phase 2: Extract workspace resolver (eliminates duplication)

1. Create `sakura-working-dir-resolution` with the session → working directory resolution
2. Replace duplicated resolution logic in claude.rs, terminal.rs, repository.rs, git.rs
3. Add tests for path resolution edge cases

### Phase 3: Extract process management (biggest testability win)

1. Create `eren-machines` from machines/ and claude/terminal handlers
2. Define `ProcessRegistry` trait for tracking running processes
3. Extract `ClaudeEventBridge` with trait-based Armin/subscription deps
4. Write tests with mock event streams

### Phase 4: Extract session orchestration

1. Create `rengoku-sessions` from session handler + secret cache
2. Define `SecretStore` trait (implementations: SQLite, keychain, Supabase)
3. Write tests for session creation flow with mock stores

### Phase 5: Extract identity and lifecycle

1. Create `sasuke-crypto` from init.rs crypto loading + utils/secrets.rs
2. Create `historia-lifecycle` from init.rs lifecycle + lifecycle.rs
3. Write tests for startup/shutdown sequences

---

## Naming Reference

Following the existing convention of anime character names with descriptive suffixes:

| Crate | Character | Series | Mnemonic |
|-------|-----------|--------|----------|
| `rengoku-sessions` | Kyojuro Rengoku | Demon Slayer | Flame Hashira — burns bright protecting session state |
| `eren-machines` | Eren Yeager | Attack on Titan | Drives processes forward relentlessly |
| `sakura-working-dir-resolution` | Sakura Haruno | Naruto | Precise and analytical — resolves the right path |
| `one-for-all-protocol` | One For All | My Hero Academia | The shared power (protocol) passed between all crates |
| `sasuke-crypto` | Sasuke Uchiha | Naruto | Sharingan — sees through encryption, guards secrets |
| `historia-lifecycle` | Historia Reiss | Attack on Titan | Oversees the kingdom's lifecycle |

---

## What This Enables

1. **Unit tests for business logic**: Each orchestrator crate can be tested with mock dependencies
2. **Faster compilation**: Changes to session logic don't recompile process management
3. **Clear ownership**: Each crate has a single responsibility with a defined API
4. **New transport options**: `one-for-all-protocol` types can be used for HTTP/WebSocket APIs without depending on Unix socket transport
5. **Handler simplification**: IPC handlers become ~20-line parameter extractors that delegate to named crates
6. **Compile-time dependency enforcement**: A handler that should only use `rengoku-sessions` can't accidentally reach into `eren-machines`'s internals
