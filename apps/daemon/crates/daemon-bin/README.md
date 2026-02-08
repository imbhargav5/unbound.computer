# Daemon Bin

The **main binary entry point** for the Unbound daemon. It wires together all specialized crates into a single long-running process that serves the macOS app over Unix domain sockets.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        unbound-daemon                                │
│                                                                      │
│  CLI (clap)                                                          │
│    ├── start [--foreground]                                          │
│    ├── stop                                                          │
│    └── status                                                        │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                      IPC Server (Unix Socket)                  │  │
│  │                                                                │  │
│  │  health ─── auth ─── session ─── message ─── repository       │  │
│  │  claude ─── terminal ─── git ─── subscription                 │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                              │                                       │
│              ┌───────────────┼───────────────┐                       │
│              ▼               ▼               ▼                       │
│         ┌────────┐    ┌──────────┐    ┌──────────┐                  │
│         │ Armin  │    │   Deku   │    │ Piccolo  │                  │
│         │(state) │    │ (Claude) │    │  (git)   │                  │
│         └────────┘    └──────────┘    └──────────┘                  │
│              │                                                       │
│     ┌────────┼────────┐                                             │
│     ▼        ▼        ▼                                             │
│  Toshinori  Levi  AblyRealtime  Gyomei                              │
│  (sink)    (cold)   (hot)      (files)                              │
└─────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Platform Services: SQLite, Keychain, Supabase, Claude CLI          │
└─────────────────────────────────────────────────────────────────────┘
```

## CLI

```
unbound-daemon start [--foreground]   # Start the daemon
unbound-daemon stop                   # Stop the daemon gracefully (or force kill)
unbound-daemon status                 # Check if daemon is running + version
unbound-daemon --log-level debug ...  # Set log verbosity (default: info)
```

## Initialization Sequence

On `start`, the daemon boots services in dependency order:

1. **Singleton check** - Ensure no other daemon is running (via socket probe)
2. **File system setup** - Create directories, write PID file
3. **IPC server** - Bind Unix socket
4. **Toshinori** - Supabase sync sink
5. **Armin** - Session engine (SQLite-backed)
6. **Database** - Async SQLite executor
7. **SecretsManager** - Platform keychain access
8. **SupabaseClient** - REST API client
9. **Levi** - Supabase message sync worker (cold path)
10. **AblyRealtimeSyncer** - Ably hot-path message publish worker (when `ABLY_API_KEY` is set)
11. **Gyomei** - Rope-backed file I/O with cache
12. **Handler registration** - Wire IPC methods to handlers
13. **Listen** - Accept client connections

When Ably hot-path is enabled, the daemon also ensures a Falco sidecar is available.
It will use an existing Falco socket if present, otherwise it spawns the Falco binary
packaged alongside the daemon and waits for `~/.unbound/falco.sock` before enabling hot-sync.

## Shared State

All handlers share a `DaemonState` (cheap to clone via Arc):

| Field | Type | Purpose |
|-------|------|---------|
| `armin` | `Arc<DaemonArmin>` | Session engine (snapshot + delta views) |
| `db` | `AsyncDatabase` | Thread-safe SQLite executor |
| `secrets` | `Arc<Mutex<SecretsManager>>` | Platform keychain access |
| `gyomei` | `Arc<Gyomei>` | Cached file I/O |
| `config` | `Arc<Config>` | Supabase URLs, relay config |
| `paths` | `Arc<Paths>` | Socket, PID, database paths |
| `toshinori` | `Arc<ToshinoriSink>` | Supabase change sink |
| `message_sync` | `Arc<Levi>` | Message sync worker |
| `realtime_message_sync` | `Option<Arc<AblyRealtimeSyncer>>` | Ably hot-path message sync worker |
| `supabase_client` | `Arc<SupabaseClient>` | REST API for device management |
| `session_sync` | `Arc<SessionSyncService>` | Background session sync |
| `session_secret_cache` | `SessionSecretCache` | In-memory secret lookup |
| `claude_processes` | `Arc<Mutex<HashMap>>` | Active Claude CLI processes |
| `terminal_processes` | `Arc<Mutex<HashMap>>` | Active terminal processes |

## IPC Handlers

Every IPC method maps to a handler that extracts params, validates, delegates to a crate, and returns a JSON response.

| Domain | Methods | Backing Crate |
|--------|---------|---------------|
| Health | `health`, `shutdown`, `outbox.status` | - |
| Auth | `auth.login`, `auth.complete_social`, `auth.status`, `auth.logout` | ymir |
| Sessions | `session.list`, `session.create`, `session.get`, `session.delete` | armin |
| Messages | `message.list`, `message.send` | armin |
| Repos | `repository.list`, `repository.add`, `repository.remove` | armin |
| Files | `repository.list_files`, `repository.read_file`, `repository.write_file`, ... | gyomei, yagami |
| Claude | `claude.send`, `claude.status`, `claude.stop` | deku, eren-machines |
| Terminal | `terminal.run`, `terminal.status`, `terminal.stop` | eren-machines |
| Git | `git.status`, `git.diff_file`, `git.log`, `git.branches`, `git.stage`, ... | piccolo |
| Streaming | `session.subscribe`, `session.unsubscribe` | daemon-ipc |

## Side-Effect Bridge

The `armin_adapter` composes two sinks so every Armin commit fans out:

```
Armin commit
    ├──► DaemonSideEffectSink  -> broadcast to IPC clients
    └──► ToshinoriSink
            ├──► Levi (cold path) -> Supabase messages/session tables
            └──► AblyRealtimeSyncer (hot path) -> Falco -> Ably
```

`MessageAppended` is fanned out to both cold and hot paths. Hot path uses channel
`session:{session_id}:conversation` with event `conversation.message.v1`.

## Crate Structure

```
daemon-bin/
├── Cargo.toml
└── src/
    ├── main.rs                     # CLI entry point (clap)
    ├── app/
    │   ├── init.rs                 # Boot sequence
    │   ├── lifecycle.rs            # Stop / status commands
    │   └── state.rs                # DaemonState definition
    ├── auth/
    │   ├── login.rs                # OAuth + device registration
    │   ├── logout.rs               # Token revocation + cleanup
    │   └── status.rs               # Session validity check
    ├── ipc/
    │   ├── register.rs             # Handler registration
    │   └── handlers/
    │       ├── health.rs
    │       ├── git.rs
    │       ├── message.rs
    │       ├── session.rs
    │       ├── repository.rs
    │       ├── claude.rs
    │       └── terminal.rs
    ├── machines/
    │   ├── claude/stream.rs        # Claude event → Armin bridge
    │   ├── terminal/stream.rs      # Terminal output → Armin bridge
    │   └── git/operations.rs       # Piccolo wrappers
    ├── armin_adapter.rs            # Composite side-effect sink
    └── utils/
        ├── secrets.rs              # Key derivation helpers
        └── session_secret_cache.rs # In-memory secret cache
```

## Lifecycle

**Startup**: Singleton check → service init → handler registration → listen loop

**Shutdown**: `shutdown` IPC method → tokio cancellation → cleanup PID + socket files

**Stop command**: Sends `shutdown` IPC call → waits 3s → SIGKILL if still running

## Dependencies

This crate depends on nearly every other workspace crate:

- **armin** - Session/message storage engine
- **daemon-config-and-utils** - Config, paths, logging, crypto primitives
- **daemon-ipc** - Unix socket server and protocol
- **daemon-database** - Async SQLite persistence
- **daemon-storage** - Platform keychain
- **ymir** - OAuth flow and token/session management
- **toshinori** - Supabase sync sink
- **levi** - Message sync worker
- **daemon-falco** (runtime process) - Ably publisher for hot-path payloads
- **deku** - Claude CLI process manager
- **piccolo** - Native git operations (libgit2)
- **gyomei** - Rope-backed file I/O
- **yagami** - Directory listing
- **eren-machines** - Process registry and event bridge
- **historia-lifecycle** - PID/singleton management
- **rengoku-sessions** - Session orchestration
- **sakura-working-dir-resolution** - Working directory resolution
- **sasuke-crypto** - Device identity and key management
