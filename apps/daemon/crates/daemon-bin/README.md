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
10. **daemon-ably sidecar** - Shared Ably transport process (only when authenticated context exists)
11. **AblyRealtimeSyncer + Falco sidecar** - Hot-path message publish chain (`Armin -> Falco -> daemon-ably -> Ably`)
12. **Nagato server + Nagato sidecar** - Remote command ingress bridge (`Ably -> daemon-ably -> Nagato -> daemon`)
13. **Sidecar log capture** - Stream sidecar stdout/stderr into observability
14. **Gyomei** - Rope-backed file I/O with cache
15. **Handler registration** - Wire IPC methods to handlers
16. **Listen** - Accept client connections

The daemon starts the Ably token broker (`~/.unbound/ably-auth.sock`) and mints audience-scoped tokens.
`daemon-ably` receives those broker credentials and exposes one local socket at `~/.unbound/ably.sock`.
Falco and Nagato only receive `UNBOUND_ABLY_SOCKET`; they never receive broker tokens or raw Ably API keys.

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
| GitHub | `gh.auth_status`, `gh.pr_create`, `gh.pr_view`, `gh.pr_list`, `gh.pr_checks`, `gh.pr_merge` | bakugou |
| Streaming | `session.subscribe`, `session.unsubscribe` | daemon-ipc |

## Side-Effect Bridge

The `armin_adapter` composes two sinks so every Armin commit fans out:

```
Armin commit
    ├──► DaemonSideEffectSink  -> broadcast to IPC clients
    └──► ToshinoriSink
            ├──► Levi (cold path) -> Supabase messages/session tables
            └──► AblyRealtimeSyncer (hot path) -> Falco -> daemon-ably -> Ably
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

## Token Auth Migration Checklist

- `api/v1/mobile/ably/token` supports audience-scoped token issuance (`daemon_falco` / `daemon_nagato` / mobile audiences).
- Daemon Ably broker (`~/.unbound/ably-auth.sock`) is running and sidecars authenticate with broker tokens.
- `daemon-ably` receives broker envs (`UNBOUND_ABLY_BROKER_SOCKET`, `UNBOUND_ABLY_BROKER_TOKEN_FALCO`, `UNBOUND_ABLY_BROKER_TOKEN_NAGATO`).
- Runtime sidecars (`falco`, `nagato`) use local transport env only (`UNBOUND_ABLY_SOCKET`).
- iOS clients use token auth callback only (no `ABLY_API_KEY` fallback path).
- Logout clears broker token cache, tears down daemon-ably/Falco/Nagato sidecars, and removes `ably.sock`, `falco.sock`, `nagato.sock`.
- Manual key rotation reminder: rotate legacy Ably API keys in server-side secret storage and revoke old keys after rollout verification.

## Presence Heartbeat Contract

`daemon-ably` emits message-based presence heartbeats for iOS remote-command gating.

| Field | Value |
|-------|-------|
| Channel | `session:presence:{user_id}:conversation` |
| Event | `daemon.presence.v1` |
| Producer | `daemon-ably` |
| Status values | `online`, `offline` |
| Online cadence | immediate publish on startup + periodic heartbeat |
| Offline signal | best-effort publish during graceful shutdown |

Payload schema:

```json
{
  "schema_version": 1,
  "user_id": "user-uuid",
  "device_id": "device-uuid",
  "status": "online",
  "source": "daemon-ably",
  "sent_at_ms": 1739030400000
}
```

## Regression Matrix

Use this matrix for QA and release checks after sidecar changes:

| Scenario | Expected Result |
|----------|-----------------|
| Falco side-effect publish with channel/event/payload overrides | Override behavior matches pre-migration output exactly |
| Nagato command handling under load | One-in-flight processing remains enforced |
| Nagato daemon timeout | Fail-open behavior publishes timeout ACK and continues |
| daemon-ably restart while daemon stays up | Falco/Nagato recover transport without process restart |
| Login/logout transitions | Sidecars start/stop deterministically and sockets are cleaned |
| iOS target-device gating | Remote actions disable after heartbeat TTL and re-enable after next heartbeat |

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
- **daemon-ably** (runtime process) - Shared Ably transport + heartbeat publisher
- **daemon-falco** (runtime process) - Ably publisher for hot-path payloads
- **daemon-nagato** (runtime process) - Remote command ingress sidecar
- **deku** - Claude CLI process manager
- **piccolo** - Native git operations (libgit2)
- **gyomei** - Rope-backed file I/O
- **yagami** - Directory listing
- **eren-machines** - Process registry and event bridge
- **historia-lifecycle** - PID/singleton management
- **rengoku-sessions** - Session orchestration
- **sakura-working-dir-resolution** - Working directory resolution
- **sasuke-crypto** - Device identity and key management
