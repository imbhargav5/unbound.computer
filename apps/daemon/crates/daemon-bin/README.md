# Daemon Bin

Main binary entry point for the local Unbound daemon.

`daemon-bin` wires together IPC transport, session persistence, board domain
services, process managers, repository file operations, and observability into
one long-running process (`unbound-daemon`).

## Architecture

```
macOS App / CLI
       |
       | Unix Socket (NDJSON)
       v
+-------------------------------+
|        unbound-daemon         |
|                               |
|  IPC handlers                 |
|   - board/session/message     |
|   - repository/file ops       |
|   - claude/terminal           |
|   - git/gh/system             |
|                               |
|  Shared state                 |
|   - Armin session engine      |
|   - Async SQLite executor     |
|   - Secrets manager           |
|   - SafeFileOps               |
|   - process registries        |
+-------------------------------+
       |
       +--> SQLite (`unbound.sqlite`)
       +--> Keychain/secure storage
       +--> Claude CLI / terminal processes
```

## CLI

```bash
unbound-daemon start [--foreground] [--base-dir <path>]
unbound-daemon stop [--base-dir <path>]
unbound-daemon status [--base-dir <path>]
unbound-daemon --log-level debug start --foreground
```

`--base-dir` overrides runtime file paths (socket, pid, logs, config).

## Startup Sequence

On `start`, the daemon performs a critical bootstrap sequence:

1. Enforce singleton (probe socket, remove stale runtime files)
2. Ensure runtime directories exist
3. Write PID file
4. Initialize IPC server
5. Open Armin session engine
6. Open async SQLite database
7. Initialize secure storage and local device identity/keys
8. Build shared `DaemonState`
9. Register IPC handlers
10. Start IPC server and wait for socket readiness
11. Mark startup status as `ready`

Startup progress is written to `startup-status.json` for diagnostics.

## Shared State

All handlers clone a shared `DaemonState` (Arc + Mutex/RwLock internals):

- `armin`: session engine + side-effect source
- `db`: async SQLite executor
- `secrets`: platform secrets manager
- `safe_file_ops`: rope-backed file IO helpers
- `subscriptions`: event fanout manager for IPC subscriptions
- `session_secret_cache`: decrypted session secret cache
- `claude_processes` / `terminal_processes`: in-flight process registries
- `device_id`, `device_private_key`, `db_encryption_key`: local identity+crypto material
- `paths`, `config`: runtime configuration and filesystem layout

## IPC Method Domains

Handlers are registered in modules under `src/ipc/handlers`:

- Health/lifecycle: `health`, `shutdown`
- Board: company/agent/goal/project/issue/approval/workspace methods
- Sessions and messages
- Repository CRUD + repository settings + safe file operations
- Claude process control and streaming
- Terminal process control and streaming
- Git operations
- GitHub CLI operations
- System dependency checks

## Side-Effect Bridge

`armin_adapter` maps Armin side-effects into IPC events:

- Session create/delete -> global subscription events
- Message append -> per-session `message` events
- Runtime status updates -> per-session `status_change` events

Event payloads include sequence numbers and can carry trace context.

## Lifecycle Behavior

- `status` checks health endpoint over the daemon socket.
- `stop` requests graceful `shutdown`, waits up to 3 seconds, then falls back to
  SIGKILL when the PID still points to `unbound-daemon`.
- Runtime cleanup removes socket and pid files on shutdown.

## Crate Layout

```
daemon-bin/
├── Cargo.toml
└── src/
    ├── main.rs
    ├── app/
    │   ├── init.rs
    │   ├── lifecycle.rs
    │   ├── startup_status.rs
    │   └── state.rs
    ├── ipc/
    │   ├── register.rs
    │   └── handlers/
    ├── machines/
    │   ├── claude/
    │   ├── terminal/
    │   └── git/
    ├── armin_adapter.rs
    ├── observability.rs
    ├── types/
    └── utils/
```
