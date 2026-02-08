# Eren Machines

**Process lifecycle management (Claude CLI, terminal) for the Unbound daemon.** Eren owns the process registry and the event bridges that convert external process output into Armin messages.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           Daemon                                 │
│                                                                  │
│  IPC Handler ──► ProcessRegistry::register() ──► stop channel   │
│       │                    │                          │          │
│       │                    │                          ▼          │
│       │              HashMap<SessionId, Sender>   broadcast     │
│       │                                              │          │
│       ├──► claude_bridge::store_event()              │          │
│       │         │                                    │          │
│       │         ▼                                    │          │
│       │    Armin (message storage)                   │          │
│       │                                              │          │
│       └──► terminal_bridge::store_stdout()           │          │
│                 │                                    │          │
│                 ▼                                    │          │
│            Armin (message storage)                   │          │
│                                                      │          │
│  ProcessRegistry::stop() ◄───────────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Process Registry

The `ProcessRegistry` tracks running processes by session ID and provides stop signals via broadcast channels.

```rust
use eren_machines::ProcessRegistry;

let registry = ProcessRegistry::new();

// Register a process for a session
let stop_tx = registry.register("session-123")?;

// Subscribe to stop signals (give to spawned task)
let mut stop_rx = stop_tx.subscribe();

// Check status
assert_eq!(registry.status("session-123"), ProcessStatus::Running);
assert_eq!(registry.count(), 1);

// Stop the process (sends signal, removes from registry)
registry.stop("session-123"); // returns true if found

// Or clean up after natural exit
registry.remove("session-123");
```

### Registry API

| Method | Description |
|--------|-------------|
| `register(session_id)` | Register process, returns stop channel. Fails if already running. |
| `stop(session_id)` | Send stop signal, remove entry. Returns `true` if found. |
| `remove(session_id)` | Clean up entry after process exits naturally. |
| `status(session_id)` | `Running` or `NotRunning` |
| `count()` | Number of active processes |
| `is_empty()` | Any processes running? |
| `session_ids()` | List all active session IDs |

### Lifecycle Pattern

1. Handler calls `register()` to get a `broadcast::Sender<()>`
2. Spawned task subscribes to the sender for stop signals
3. On user stop request: `stop()` sends signal and removes entry
4. On natural exit: `remove()` cleans up the entry
5. Re-registration is allowed after stop or remove

## Claude Bridge

Converts Claude CLI JSON events into Armin session messages.

```rust
use eren_machines::claude_bridge;

// Store a raw Claude JSON event as a message
let msg = claude_bridge::store_event(&armin, session_id, raw_json)?;

// Update the Claude session ID
claude_bridge::update_claude_session_id(&armin, session_id, "claude-sess-abc")?;

// Track agent status
claude_bridge::set_running(&armin, session_id)?;
claude_bridge::set_idle(&armin, session_id)?;
```

## Terminal Bridge

Converts terminal process output into structured Armin messages.

```rust
use eren_machines::terminal_bridge;

// Store stdout/stderr lines
terminal_bridge::store_stdout(&armin, session_id, "build succeeded")?;
terminal_bridge::store_stderr(&armin, session_id, "warning: unused var")?;

// Store exit event
terminal_bridge::store_finished(&armin, session_id, Some(0))?;
```

Messages are stored as JSON:

```json
{"type": "terminal_output", "stream": "stdout", "content": "build succeeded"}
{"type": "terminal_output", "stream": "stderr", "content": "warning: unused var"}
{"type": "terminal_finished", "exit_code": 0}
```

## Error Types

```rust
pub enum ProcessError {
    AlreadyRunning(String),   // Process already exists for this session
    NotRunning(String),       // No process found for this session
    Armin(ArminError),        // Underlying storage error
}
```

## Design Principles

- **Lightweight coordination**: No actual process spawning here - just lifecycle tracking
- **Broadcast channels**: Clean async stop signaling with multiple subscribers
- **Generic writers**: Bridge functions accept `&impl SessionWriter` for testability
- **Session-scoped**: One process per session, enforced by the registry

## Testing

```bash
cargo test -p eren-machines
```

26 tests covering registry operations, bridge message formats, sequence tracking, and error handling.
