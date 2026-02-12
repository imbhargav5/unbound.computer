# daemon-falco

Falco is a **stateless, crash-safe publisher** that receives Armin side-effects from the daemon and publishes them to Ably for real-time sync.

## Core Purpose

> **Falco publishes committed reality to Ably.**

When Armin commits a fact to SQLite, it emits a side-effect. The daemon forwards these side-effects to Falco, which publishes them to Ably for other devices/clients to receive.

Falco authenticates to Ably via the daemon-local broker socket (`~/.unbound/ably-auth.sock`).
It does not use `ABLY_API_KEY` directly.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                            Daemon                                    │
│                                                                      │
│  Armin → SQLite commit → side-effect → SideEffectSink               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Unix Domain Socket (binary protocol)
                              │ ~/.unbound/falco.sock
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            Falco                                     │
│                                                                      │
│  • Receives SideEffectFrame from daemon                             │
│  • Publishes to a default channel or per-message override channel   │
│  • Sends PublishAckFrame back to daemon                             │
│  • Handles backpressure and retries                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Ably Realtime Publish
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            Ably                                      │
│ Default channel: device-events:{device_id}                           │
│ Override channel example: session:{session_id}:conversation          │
│                                                                      │
│  ┌───────────────┬───────────────────────────────┬───────────────┐  │
│  │ session_created │ conversation.message.v1      │ ...           │  │
│  │ repository_...  │ session_updated              │               │  │
│  └───────────────┴───────────────────────────────┴───────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Armin Side-Effects

Falco publishes these side-effects to Ably:

| Side-Effect | Description |
|-------------|-------------|
| `RepositoryCreated` | A new repository was registered |
| `RepositoryDeleted` | A repository was removed |
| `SessionCreated` | A new session was created |
| `SessionClosed` | A session was closed |
| `SessionDeleted` | A session was deleted |
| `SessionUpdated` | Session metadata changed |
| `MessageAppended` | A message was added to a session |
| `AgentStatusChanged` | Agent status changed (idle/running/waiting/error) |
| `OutboxEventsSent` | Outbox events were sent |
| `OutboxEventsAcked` | Outbox events were acknowledged |

## Publish Envelope Overrides

Falco accepts a standard side-effect payload and supports three optional overrides:

- `channel`: publish to a channel different from Falco's default `device-events:{device_id}`
- `event`: publish with a custom event name instead of `type`
- `payload`: publish this raw JSON body instead of the full side-effect envelope

This is used by Toshinori's Ably hot path for conversation messages. Example envelope sent to Falco:

```json
{
  "type": "message_appended",
  "channel": "session:session-123:conversation",
  "event": "conversation.message.v1",
  "payload": {
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
}
```

## Binary Protocol

Falco communicates with the daemon using a length-prefixed binary protocol over Unix Domain Sockets.

### Frame Format
```
[4 bytes: length (LE u32)][payload bytes]
```

### SideEffectFrame (Daemon -> Falco)
```
Offset  Size  Field
0       4     total_len (LE u32)
4       1     type = 0x03
5       1     flags
6       2     reserved
8       16    effect_id (UUID bytes)
24      4     payload_len (LE u32)
28      N     json_payload (side-effect as JSON)
```

### PublishAckFrame (Falco -> Daemon)
```
Offset  Size  Field
0       4     total_len (LE u32)
4       1     type = 0x04
5       1     status (0x01=SUCCESS, 0x02=FAILED)
6       2     reserved
8       16    effect_id (UUID bytes)
24      4     error_len (LE u32)
28      N     error_message (if failed)
```

## Process Model

The daemon spawns Falco as a child process:

1. Daemon starts and spawns Falco with device ID
2. Falco creates `falco.sock` and listens for connections
3. Daemon connects to Falco's socket
4. When Armin emits side-effects, daemon sends SideEffectFrame
5. Falco publishes to Ably and sends PublishAckFrame
6. On shutdown, daemon terminates Falco

## Non-Negotiable Invariants

1. **Publish-After-Commit**: Side-effects are only received after SQLite commit
2. **At-Least-Once Delivery**: Falco retries failed publishes
3. **Ordered Per-Session**: Messages within a session maintain order
4. **Crash-Safe**: Daemon tracks unacked effects; can resend on restart

## Installation

```bash
cd packages/daemon-falco
go build -o falco ./cmd/falco
```

## Usage

```bash
# Set required environment variables
export UNBOUND_ABLY_BROKER_SOCKET="$HOME/.unbound/ably-auth.sock"
export UNBOUND_ABLY_BROKER_TOKEN="broker-token-issued-by-daemon"

# Run Falco
./falco --device-id "device-uuid-here"

# With debug logging
./falco --device-id "device-uuid-here" --debug
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `UNBOUND_ABLY_BROKER_SOCKET` | (required) | Daemon-local Ably broker Unix socket path |
| `UNBOUND_ABLY_BROKER_TOKEN` | (required) | Broker auth token for Falco audience |
| `FALCO_SOCKET` | `~/.unbound/falco.sock` | Unix socket path |
| `FALCO_PUBLISH_TIMEOUT` | `5` | Ably publish timeout in seconds |

## Package Structure

```
packages/daemon-falco/
├── cmd/falco/main.go       # CLI entry point
├── config/config.go        # Configuration management
├── publisher/publisher.go  # Ably publisher
├── server/server.go        # Unix socket server
├── protocol/
│   ├── protocol.go         # Binary wire protocol
│   └── protocol_test.go    # Protocol tests
├── sideeffect/
│   └── types.go            # Side-effect types (mirrors Armin)
├── go.mod
├── go.sum
└── README.md
```

## Error Handling

| Error Type | Action |
|-----------|--------|
| Ably connection lost | Reconnect with backoff |
| Publish timeout | Retry up to 3 times, then fail |
| Socket error | Log and continue |
| Invalid frame | Log error, skip frame |

## Logging

Falco uses structured logging with zap. Log levels:

| Level | Use Case |
|-------|----------|
| `DEBUG` | Frame details, publish attempts |
| `INFO` | Successful publishes, connections |
| `WARN` | Retries, transient failures |
| `ERROR` | Persistent failures |

Enable debug logging with `--debug` flag.
