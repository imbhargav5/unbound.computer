# Falco

Falco is a **stateless, crash-safe, content-agnostic courier** that moves encrypted commands from Redis Streams to a local daemon. It ACKs Redis only when explicitly permitted by the daemon or when a timeout expires.

## Core Authority Rule

> **Falco MUST NOT ACK Redis unless the daemon explicitly instructs it to, OR a safety timeout expires.**

This rule ensures:
- The daemon has full control over command processing
- Crashed commands are automatically redelivered
- No command is ever lost due to premature acknowledgment

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Redis Streams                              │
│                   remote:commands:{device_id}                        │
│                                                                      │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐         │
│  │  msg-id-1   │  msg-id-2   │  msg-id-3   │  msg-id-4   │   ...   │
│  │ encrypted   │ encrypted   │ encrypted   │ encrypted   │         │
│  │  payload    │  payload    │  payload    │  payload    │         │
│  └─────────────┴─────────────┴─────────────┴─────────────┘         │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ XREADGROUP (consumer group: "falco")
                              │ COUNT=1, BLOCK 5000
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            Falco                                     │
│                                                                      │
│  • Reads ONE message at a time                                       │
│  • Generates command_id (UUID)                                       │
│  • Forwards encrypted payload to daemon                              │
│  • Waits for daemon decision (ACK_REDIS or DO_NOT_ACK)              │
│  • ACKs Redis only on daemon instruction or timeout                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Unix Domain Socket (binary protocol)
                              │ ~/.unbound/falco.sock
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            Daemon                                    │
│                                                                      │
│  • Receives encrypted payload via CommandFrame                       │
│  • Decrypts and validates command                                    │
│  • Executes command (session creation, message processing, etc.)    │
│  • Sends DaemonDecisionFrame (ACK_REDIS or DO_NOT_ACK)              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Redis Stream Design

### Stream Naming
```
remote:commands:{device_id}
```

### Consumer Group
```
Group name: falco
Consumer name: falco-{uuid}
```

### XREADGROUP Semantics

Falco uses `XREADGROUP` with:
- `COUNT=1`: Process one message at a time
- `BLOCK 5000`: 5-second blocking read
- `NOACK`: Not used (we manage ACKs explicitly)

Messages remain in the Pending Entries List (PEL) until explicitly ACKed.

## Binary Protocol

Falco communicates with the daemon using a length-prefixed binary protocol over Unix Domain Sockets.

### Frame Format
```
[4 bytes: length (LE u32)][payload bytes]
```

### CommandFrame (Falco -> Daemon)
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

### DaemonDecisionFrame (Daemon -> Falco)
```
Offset  Size  Field
0       4     total_len (LE u32)
4       1     type = 0x02
5       1     decision (0x01=ACK_REDIS, 0x02=DO_NOT_ACK)
6       2     reserved
8       16    command_id (UUID bytes)
24      4     result_len (LE u32)
28      N     optional_result
```

## Timeout Behavior (Fail-Open)

If the daemon does not respond within the timeout period (default: 15 seconds), Falco will ACK the message in Redis. This is a **fail-open escape hatch** to prevent:

- Infinite PEL growth from crashed daemons
- Stuck commands blocking the queue forever

The timeout should be set high enough to allow for:
- Command decryption
- Command execution
- Any downstream processing

## Process Model

The daemon spawns Falco as a child process:

1. Daemon starts and ensures `falco.sock` is listening
2. Daemon spawns Falco with device ID
3. Falco connects to Redis and daemon
4. Falco runs the main courier loop
5. On shutdown, daemon terminates Falco

## Non-Negotiable Invariants

1. **Content-Agnostic**: Falco never inspects or modifies encrypted payloads
2. **ACK-Gated**: Redis is ACKed only on daemon instruction or timeout
3. **One In-Flight**: Only one command processed at a time (COUNT=1)
4. **Crash-Safe**: Any crash results in automatic Redis redelivery

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://127.0.0.1:6379` | Redis connection URL |
| `FALCO_SOCKET` | `~/.unbound/falco.sock` | Unix socket path |
| `FALCO_TIMEOUT_SECS` | `15` | Daemon response timeout |
| `FALCO_BLOCK_MS` | `5000` | XREADGROUP block timeout |

## Admin Operations

### View Pending Messages
```bash
redis-cli XPENDING remote:commands:{device_id} falco
```

### View Detailed PEL
```bash
redis-cli XPENDING remote:commands:{device_id} falco - + 10
```

### Claim Orphaned Messages
```bash
redis-cli XCLAIM remote:commands:{device_id} falco falco-new 60000 {message_id}
```

### Manual ACK (Use with Caution)
```bash
redis-cli XACK remote:commands:{device_id} falco {message_id}
```

### Create Consumer Group
```bash
redis-cli XGROUP CREATE remote:commands:{device_id} falco $ MKSTREAM
```

## Recovery Procedures

### Stuck Messages in PEL

1. Check XPENDING for stuck messages
2. If daemon is healthy, XCLAIM to a new consumer
3. If message is corrupted, manually XACK (logs the loss)

### Consumer Group Missing

If the consumer group doesn't exist:
```bash
redis-cli XGROUP CREATE remote:commands:{device_id} falco 0 MKSTREAM
```

Use `0` to reprocess all existing messages, or `$` to start from new messages only.
