# Toshinori

Toshinori is the daemon-side **fanout sink** for Armin side-effects:

- cold path: sync durable state to Supabase
- hot path: publish encrypted conversation messages to Ably via Falco

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────┐
│                                  Daemon                                  │
│                                                                           │
│ Armin (SQLite commit) -> SideEffect -> ToshinoriSink                     │
│                                       |                                   │
│                                       | MessageAppended fanout            │
│                    +------------------+------------------+                │
│                    |                                     |                │
│             enqueue to Levi                      enqueue to AblyRealtime  │
└────────────────────|─────────────────────────────|────────────────────────┘
                     |                             |
               async HTTP (cold)             Falco socket (hot)
                     v                             v
              Supabase tables               daemon-falco -> Ably
```

## Design Principles

- **Non-blocking**: side-effect handling is async and never blocks Armin commits
- **Fire-and-forget**: sync failures are logged and retried by workers
- **Single encryption utility**: conversation payload encryption uses shared helpers from `daemon-config-and-utils`
- **Context-aware**: sync workers run only when auth context is present
- **Coalesced runtime status**: frequent status updates are merged and de-duped

## Message Sync Paths

| Path | Worker | Target | Purpose |
|------|--------|--------|---------|
| Cold | `Levi` | Supabase `messages` table | Durable cross-device sync |
| Hot | `AblyRealtimeSyncer` | Ably `session:{session_id}:conversation` | Fast realtime delivery |

The two paths are independent: hot-path publish does not change Supabase cold-sync logic.

## Runtime Status Sync Paths

| Path | Worker | Target | Purpose |
|------|--------|--------|---------|
| Cold | `ToshinoriClient` | Supabase `agent_coding_sessions.runtime_status` | Durable runtime status mirror |
| Hot | `AblyRuntimeStatusSyncer` | Ably LiveObjects (`session:{session_id}:status`) | Realtime status object updates |

## Usage

```rust
use std::sync::Arc;
use toshinori::{SyncContext, ToshinoriSink};

let sink = Arc::new(ToshinoriSink::new(
    "https://xyz.supabase.co",
    "anon-key",
    tokio::runtime::Handle::current(),
));

sink.set_context(SyncContext {
    access_token: "user-access-token".to_string(),
    user_id: "user-uuid".to_string(),
    device_id: "device-uuid".to_string(),
}).await;

// Register workers (constructed elsewhere)
// sink.set_message_syncer(levi_syncer).await;
// sink.set_realtime_message_syncer(ably_syncer).await;

// On logout
sink.clear_context().await;
```

## Side-Effects Handled

| Side-Effect | Supabase (cold) | Ably hot path |
|-------------|------------------|---------------|
| `RepositoryCreated` | Skipped by default (needs metadata) | No-op |
| `RepositoryDeleted` | Delete from `repositories` | No-op |
| `SessionCreated` | Upsert `agent_coding_sessions` (needs metadata) | No-op |
| `SessionClosed` | Update session status to `ended` | No-op |
| `SessionDeleted` | Delete from `agent_coding_sessions` | No-op |
| `SessionUpdated` | Upsert `agent_coding_sessions` (needs metadata) | No-op |
| `MessageAppended` | Enqueue Levi sync | Enqueue Ably realtime sync |
| `AgentStatusChanged` | Skipped | No-op |
| `RuntimeStatusUpdated` | Update `runtime_status` JSON | Enqueue LiveObjects object-set |

## Ably Conversation Message Contract

For each `MessageAppended`, the realtime worker publishes:

- channel: `session:{session_id}:conversation`
- event: `conversation.message.v1`
- payload:

```json
{
  "schema_version": 1,
  "session_id": "session-123",
  "message_id": "message-456",
  "sequence_number": 42,
  "sender_device_id": "device-abc",
  "created_at_ms": 1739030400000,
  "encryption_alg": "chacha20poly1305",
  "content_encrypted": "...base64...",
  "content_nonce": "...base64..."
}
```

`content_encrypted` and `content_nonce` are produced from the shared conversation crypto utility.

## Ably Runtime Status Contract

Runtime status updates are published via Falco object-set operations:

- channel: `session:{session_id}:status`
- object key: `coding_session_status`
- payload: `RuntimeStatusEnvelope`

```json
{
  "schema_version": 1,
  "coding_session": {
    "status": "running",
    "error_message": null
  },
  "device_id": "device-abc",
  "session_id": "session-123",
  "updated_at_ms": 1739030400000
}
```

## Error Handling

- Errors are logged and do not propagate back to Armin commit paths
- Worker-level retries/backoff are handled in Levi and AblyRealtimeSyncer
- Missing auth context causes syncs to be skipped safely

## Metadata Requirements

Session upserts require metadata not present in raw Armin side-effects. Provide a
`SessionMetadataProvider` to enable `SessionCreated`/`SessionUpdated` upserts.
