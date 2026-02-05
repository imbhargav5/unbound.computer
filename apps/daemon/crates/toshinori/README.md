# Toshinori

Toshinori is a **Supabase sync sink** for Armin side-effects. When Armin commits facts to SQLite, Toshinori asynchronously syncs those changes to Supabase for cross-device visibility.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                            Daemon                                    │
│                                                                      │
│  Armin (SQLite) ─── commit ──► SideEffect ──► ToshinoriSink         │
│                                                      │               │
└──────────────────────────────────────────────────────┼───────────────┘
                                                       │
                                                       │ async HTTP
                                                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          Supabase                                    │
│                                                                      │
│  ┌───────────────┐  ┌─────────────────────────┐  ┌──────────────┐  │
│  │ repositories  │  │ agent_coding_sessions   │  │  messages    │  │
│  └───────────────┘  └─────────────────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Design Principles

- **Non-blocking**: Side-effect handling is async and doesn't block Armin
- **Fire-and-forget**: Failed syncs are logged but don't fail the operation
- **Idempotent**: Uses upsert operations for safe retries
- **Context-aware**: Only syncs when authenticated (context is set)

## Usage

```rust
use toshinori::{ToshinoriSink, SyncContext};
use armin::SideEffectSink;

// Create sink with Supabase credentials
let sink = ToshinoriSink::new(
    "https://xyz.supabase.co",
    "your-anon-key",
    tokio::runtime::Handle::current(),
);

// After user authenticates, set the sync context
sink.set_context(SyncContext {
    access_token: "user-access-token".to_string(),
    user_id: "user-uuid".to_string(),
    device_id: "device-uuid".to_string(),
}).await;

// Now side-effects will be synced to Supabase
sink.emit(SideEffect::SessionCreated {
    session_id: SessionId::from_string("session-123"),
});

// On logout, clear the context
sink.clear_context().await;
```

## Side-Effects Handled

| Side-Effect | Supabase Action |
|-------------|-----------------|
| `RepositoryCreated` | **Skipped by default** (requires repository metadata) |
| `RepositoryDeleted` | Delete from `repositories` |
| `SessionCreated` | Upsert to `agent_coding_sessions` (requires session metadata) |
| `SessionClosed` | Update status to "ended" |
| `SessionDeleted` | Delete from `agent_coding_sessions` |
| `SessionUpdated` | Upsert to `agent_coding_sessions` (requires session metadata) |
| `MessageAppended` | Enqueue message sync (requires message content) |
| `AgentStatusChanged` | **Skipped** (no `agent_status` column in schema) |
| `OutboxEventsSent` | No sync needed |
| `OutboxEventsAcked` | No sync needed |

## Integration with Daemon

Toshinori is designed to work alongside the existing `DaemonSideEffectSink`:

```rust
// You can compose multiple sinks
struct CompositeSink {
    daemon_sink: DaemonSideEffectSink,  // IPC broadcasts
    toshinori: ToshinoriSink,            // Supabase sync
}

impl SideEffectSink for CompositeSink {
    fn emit(&self, effect: SideEffect) {
        self.daemon_sink.emit(effect.clone());
        self.toshinori.emit(effect);
    }
}
```

## Error Handling

Toshinori follows a **fire-and-forget** pattern:
- Errors are logged but never propagate
- Armin's commit is never blocked or rolled back
- Supabase sync failures don't affect local operation

## Metadata Requirements

Session upserts require repository metadata that is not available in Armin side-effects
alone. Provide a metadata source via `SessionMetadataProvider` to enable session sync.
Repository upserts are skipped by default for the same reason (missing `name` and
`local_path`).

This ensures the daemon remains responsive even during network issues.
