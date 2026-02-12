# daemon-nagato

Nagato is a **stateless, crash-safe consumer** that receives remote commands from Ably and forwards them to the local daemon for processing.

## Core Purpose

> **Nagato receives commands from Ably and delivers them to the daemon.**

When a remote client (e.g., mobile app, web dashboard) wants to send a command to a device, it publishes to the device's Ably channel. Nagato subscribes to this channel, receives the encrypted command, and forwards it to the daemon for execution.

Nagato authenticates to Ably via the daemon-local broker socket (`~/.unbound/ably-auth.sock`).
It does not use `ABLY_API_KEY` directly.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                            Ably                                      │
│                 Channel: remote:{device_id}:commands                 │
│                                                                      │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐         │
│  │  command-1  │  command-2  │  command-3  │  command-4  │   ...   │
│  │ encrypted   │ encrypted   │ encrypted   │ encrypted   │         │
│  │  payload    │  payload    │  payload    │  payload    │         │
│  └─────────────┴─────────────┴─────────────┴─────────────┘         │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Ably Realtime Subscribe
                              │ (one message at a time)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           Nagato                                    │
│                                                                      │
│  • Subscribes to `remote.command.v1` on device-specific channel     │
│  • Generates command_id (UUID) for each message                     │
│  • Forwards encrypted payload to daemon                              │
│  • Waits for daemon decision (ACK_MESSAGE or DO_NOT_ACK)            │
│  • Publishes command ACKs using `command_id` correlation            │
│  • Handles timeout fail-open behavior                               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Unix Domain Socket (binary protocol)
                              │ ~/.unbound/nagato.sock
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            Daemon                                    │
│                                                                      │
│  • Receives encrypted payload via CommandFrame                       │
│  • Decrypts and validates command                                    │
│  • Executes command (start session, send message, etc.)             │
│  • Sends DaemonDecisionFrame (ACK_MESSAGE or DO_NOT_ACK)            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Relationship with Falco

Nagato and Falco are complementary:

| Component | Direction | Purpose |
|-----------|-----------|---------|
| **Nagato** | Ably → Daemon | Receives remote commands |
| **Falco** | Daemon → Ably | Publishes side-effects |

Together they enable bidirectional real-time sync:
- Commands flow **in** via Nagato
- Events flow **out** via Falco

## Ably Contract

Nagato currently uses one channel and two event types:

| Direction | Channel | Event | Payload |
|-----------|---------|-------|---------|
| Remote -> Device | `remote:{device_id}:commands` | `remote.command.v1` | Encrypted command bytes/JSON |
| Device -> Remote | `remote:{device_id}:commands` | `remote.command.ack.v1` | Command ack payload |

Command ACK payload schema:

```json
{
  "schema_version": 1,
  "command_id": "uuid-v4",
  "status": "accepted",
  "created_at_ms": 1739030400000,
  "result_b64": "optional-base64-daemon-result"
}
```

`status` is one of:
- `accepted` (daemon returned `ACK_MESSAGE`)
- `rejected` (daemon returned `DO_NOT_ACK`)
- `timeout` (daemon timed out and Nagato applied fail-open)

## Binary Protocol

Nagato communicates with the daemon using a length-prefixed binary protocol over Unix Domain Sockets.

### Frame Format
```
[4 bytes: length (LE u32)][payload bytes]
```

### CommandFrame (Nagato -> Daemon)
```
Offset  Size  Field
0       4     total_len (LE u32)
4       1     type = 0x01
5       1     flags
6       2     reserved
8       16    command_id (UUID bytes)
24      4     payload_len (LE u32)
28      N     encrypted_payload
```

### DaemonDecisionFrame (Daemon -> Nagato)
```
Offset  Size  Field
0       4     total_len (LE u32)
4       1     type = 0x02
5       1     decision (0x01=ACK_MESSAGE, 0x02=DO_NOT_ACK)
6       2     reserved
8       16    command_id (UUID bytes)
24      4     result_len (LE u32)
28      N     optional_result
```

## Timeout Behavior (Fail-Open)

If the daemon does not respond within the timeout period (default: 15 seconds), Nagato applies **fail-open** semantics:

- The message is considered processed
- Processing continues with the next message
- This prevents a stuck daemon from blocking the queue

The timeout should be set high enough to allow for:
- Command decryption
- Command execution
- Any downstream processing

## Non-Negotiable Invariants

1. **Content-Agnostic**: Nagato never decrypts or rewrites command payloads
2. **One-In-Flight**: Only one command processed at a time
3. **Fail-Open Timeout**: Timeout results in continue (not block)
4. **Command-ID Correlated ACKs**: outbound ACKs are keyed by daemon `command_id`
5. **Crash-Safe**: No persistent state; Ably handles redelivery

## Installation

```bash
cd packages/daemon-nagato
go build -o nagato ./cmd/nagato
```

## Usage

```bash
# Set required environment variables
export UNBOUND_ABLY_BROKER_SOCKET="$HOME/.unbound/ably-auth.sock"
export UNBOUND_ABLY_BROKER_TOKEN="broker-token-issued-by-daemon"

# Run Nagato
./nagato --device-id "device-uuid-here"

# With debug logging
./nagato --device-id "device-uuid-here" --debug
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `UNBOUND_ABLY_BROKER_SOCKET` | (required) | Daemon-local Ably broker Unix socket path |
| `UNBOUND_ABLY_BROKER_TOKEN` | (required) | Broker auth token for Nagato audience |
| `NAGATO_SOCKET` | `~/.unbound/nagato.sock` | Unix socket path |
| `NAGATO_DAEMON_TIMEOUT` | `15` | Daemon response timeout in seconds |

## Package Structure

```
packages/daemon-nagato/
├── cmd/nagato/main.go     # CLI entry point
├── config/config.go        # Configuration management
├── consumer/consumer.go    # Ably message consumer
├── client/client.go        # Unix socket daemon client
├── courier/courier.go      # Main orchestration loop
├── protocol/
│   ├── protocol.go         # Binary wire protocol
│   └── protocol_test.go    # Protocol tests
├── go.mod
├── go.sum
└── README.md
```

## Error Handling

| Error Type | Action |
|-----------|--------|
| Ably connection lost | Reconnect with backoff (handled by Ably SDK) |
| Daemon connection error | Retry connection on next message |
| Daemon timeout | Fail-open, continue processing |
| Protocol error | Log and continue |

## Logging

Nagato uses structured logging with zap. Log levels:

| Level | Use Case |
|-------|----------|
| `DEBUG` | Frame details, message processing |
| `INFO` | Successful deliveries, connections |
| `WARN` | Timeouts, retries, rejections |
| `ERROR` | Persistent failures |

Enable debug logging with `--debug` flag.
