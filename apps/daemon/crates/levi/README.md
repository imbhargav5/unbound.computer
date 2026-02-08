# Levi

**Supabase message sync worker for the daemon.**

Levi is responsible for reliably syncing encrypted messages and sessions to Supabase with batching, retries, and cross-device secret distribution.

## Overview

The crate provides two main services:

### `Levi` - Message Sync Worker

The core message synchronization engine that:
- Receives messages via MPSC channel
- Batches messages for efficient network usage (default: 50 messages or 500ms)
- Encrypts content using XChaCha20-Poly1305 with session-specific keys
- Syncs batches to Supabase
- Handles failures with exponential backoff retries (2s → 4s → 8s → ... → 300s max)

### `SessionSyncService` - Session & Secret Sync

Handles syncing coding sessions and distributing secrets:
- Syncs repository metadata to Supabase
- Syncs session metadata with status tracking
- Distributes encrypted session secrets to all user devices using hybrid encryption

## Architecture

```
┌─────────────────┐     ┌─────────────┐     ┌──────────────┐
│  Message Queue  │────▶│    Levi     │────▶│   Supabase   │
│  (MPSC Channel) │     │  (Batcher)  │     │   (Cloud)    │
└─────────────────┘     └──────┬──────┘     └──────────────┘
                               │
                        ┌──────▼──────┐
                        │   SQLite    │
                        │   Outbox    │
                        │  (Retries)  │
                        └─────────────┘
```

### Message Flow

1. **Enqueue**: Messages are sent to Levi via `MessageSyncer::enqueue()`
2. **Buffer**: Messages accumulate until batch size or flush interval
3. **Fill**: Remaining capacity filled from SQLite outbox (retry queue)
4. **Encrypt**: Each message encrypted with its session's symmetric key
5. **Send**: Batch sent to Supabase in single API call
6. **Track**: Messages marked sent/failed in Armin, outbox updated

### Secret Distribution

Session secrets are shared across devices using hybrid encryption:

```
Device A (Owner)              Supabase                Device B (Recipient)
      │                          │                          │
      │  Generate ephemeral key  │                          │
      │  ECDH with B's pubkey    │                          │
      │  Encrypt secret          │                          │
      │                          │                          │
      │  ─────────────────────▶  │                          │
      │  Store encrypted secret  │                          │
      │                          │  ──────────────────────▶ │
      │                          │  Fetch encrypted secret  │
      │                          │  ECDH with ephemeral key │
      │                          │  Decrypt with priv key   │
```

## Configuration

```rust
pub struct LeviConfig {
    /// Maximum messages per batch (default: 50)
    pub batch_size: usize,

    /// Time before flushing incomplete batches (default: 500ms)
    pub flush_interval: Duration,

    /// Initial retry delay (default: 2s)
    pub backoff_base: Duration,

    /// Maximum retry delay cap (default: 300s)
    pub backoff_max: Duration,
}
```

### Backoff Schedule

| Retry # | Delay |
|---------|-------|
| 1       | 2s    |
| 2       | 4s    |
| 3       | 8s    |
| 4       | 16s   |
| 5       | 32s   |
| 6       | 64s   |
| 7       | 128s  |
| 8+      | 300s  |

## Usage

### Message Syncing

```rust
use levi::{Levi, LeviConfig};
use toshinori::SyncContext;

// Create and start the worker
let config = LeviConfig::default();
let levi = Levi::new(config, api_url, anon_key, armin, db_key);
levi.start();

// Set authentication context after user login
levi.set_context(SyncContext { access_token }).await;

// Messages are automatically batched and synced
levi.enqueue(MessageSyncRequest {
    message_id: "msg-123".into(),
    session_id: "session-456".into(),
    sequence_number: 1,
    content: "Hello, world!".into(),
});
```

### Session Syncing

```rust
use levi::SessionSyncService;

let service = SessionSyncService::new(
    supabase_client,
    db_pool,
    secrets_manager,
    device_id,
    device_private_key,
    secrets_cache,
);

// Sync everything for a new session
service.sync_new_session(
    session_id,
    repository_id,
    session_secret,
).await?;

// Or sync components individually
service.sync_repository(repository_id).await?;
service.sync_session(session_id, repository_id, "active").await?;
service.distribute_secret(session_id, session_secret).await?;
```

## Dependencies

| Crate | Purpose |
|-------|---------|
| `armin` | Local session storage (SQLite) |
| `toshinori` | Supabase HTTP client |
| `daemon-auth` | Supabase types and client |
| `daemon-config-and-utils` | Hybrid encryption utilities |
| `daemon-database` | Symmetric encryption (XChaCha20-Poly1305) |
| `daemon-storage` | Secrets management |

## Error Handling

### Message Sync Errors

- **Encryption failure**: Individual message marked failed, doesn't block others
- **API failure**: All messages in batch marked failed, will retry via outbox
- **No context**: Batch skipped silently (user not logged in)

### Session Sync Errors

```rust
pub enum SyncError {
    NotAuthenticated,           // User not logged in
    NoDeviceIdentity,          // Device not registered
    RepositoryNotFound(String), // Local repo missing
    Supabase(String),          // API error
    Encryption(String),        // Crypto error
}
```

## Security

- **End-to-end encryption**: Messages encrypted with session-specific keys
- **Forward secrecy**: Ephemeral ECDH keys for secret distribution
- **Key caching**: Decrypted session keys cached in memory only
- **No plaintext in transit**: All content base64-encoded ciphertext

## Testing

```bash
cargo test -p levi
```

Tests cover:
- Backoff computation and capping
- Retry timing logic
- Secret key caching
- Outbox filling with backoff skipping
- Missing secret error handling
