# Observability Architecture

## Overview

A centralized, dev-first logging system for the Unbound Rust monorepo. Services are pure **log producers** — they write structured logs and have zero knowledge of consumers, streaming mechanisms, or sink destinations.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DEV ARCHITECTURE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                              │
│  │  daemon  │    │   cli    │    │  worker  │     ... other services       │
│  │          │    │          │    │          │                              │
│  │ tracing  │    │ tracing  │    │ tracing  │                              │
│  │ macros   │    │ macros   │    │ macros   │                              │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘                              │
│       │               │               │                                     │
│       └───────────────┼───────────────┘                                     │
│                       │                                                     │
│                       ▼                                                     │
│           ┌───────────────────────┐                                         │
│           │   observability       │                                         │
│           │   crate               │                                         │
│           │                       │                                         │
│           │   init("service")     │ ← Zero config for services              │
│           │                       │                                         │
│           │   ┌───────────────┐   │                                         │
│           │   │  JsonLayer    │   │ ← Structured JSONL formatter            │
│           │   │  + EnvFilter  │   │                                         │
│           │   └───────┬───────┘   │                                         │
│           │           │           │                                         │
│           │   ┌───────▼───────┐   │                                         │
│           │   │ CentralLog    │   │ ← Append-only, flush-per-line           │
│           │   │ Writer        │   │                                         │
│           │   └───────┬───────┘   │                                         │
│           └───────────│───────────┘                                         │
│                       │                                                     │
│                       ▼                                                     │
│           ┌───────────────────────┐                                         │
│           │ ~/.unbound/logs/      │                                         │
│           │   dev.jsonl           │ ← Single central log file               │
│           └───────────┬───────────┘                                         │
│                       │                                                     │
│       ┌───────────────┼───────────────┐                                     │
│       │               │               │                                     │
│       ▼               ▼               ▼                                     │
│   ┌───────┐       ┌───────┐       ┌───────┐                                │
│   │ tail  │       │  jq   │       │ lnav  │     ... any file reader        │
│   │  -f   │       │       │       │       │                                │
│   └───────┘       └───────┘       └───────┘                                │
│                                                                             │
│                    CONSUMERS (external tools)                               │
│                    Logs are PULLED, not pushed                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Design Principles

### 1. Services Are Log Producers Only

Services call `observability::init("my-service")` once at startup, then use standard `tracing` macros. They never:

- Expose log commands or endpoints
- Create log subscriptions or IPC channels
- Know where logs go or who reads them
- Configure log routing or filtering (beyond `RUST_LOG`)

### 2. Central File Sink (Dev Mode)

All services on the same machine write to a single file:

```
~/.unbound/logs/dev.jsonl
```

Benefits:
- **One place** for all logs from all services
- **Multi-process safe** via append-only + per-line flush
- **Pull-based streaming** — readers tail the file, no push required
- **No IPC** — processes share via filesystem, not channels

### 3. Structured JSONL Format

Each line is a self-contained JSON object:

```json
{"timestamp":"2024-01-15T10:30:00.123456Z","level":"INFO","service":"daemon","pid":12345,"target":"daemon_relay::connection","message":"connected to relay","fields":{"relay_url":"wss://relay.example.com"}}
```

Core fields:
| Field | Description |
|-------|-------------|
| `timestamp` | RFC 3339 with microseconds |
| `level` | TRACE, DEBUG, INFO, WARN, ERROR |
| `service` | Service name from `init()` |
| `pid` | Process ID |
| `target` | Module path (e.g., `daemon_relay::connection`) |
| `message` | Human-readable log message |
| `fields` | Structured key-value pairs |
| `span` | Current span name (if in a span) |
| `file` | Source file (optional) |
| `line` | Source line (optional) |

### 4. Multi-Process Safety

Achieved through:

1. **Append-only opens**: `O_APPEND` flag ensures atomic appends
2. **Flush per line**: Each log line is flushed immediately
3. **No coordination**: Processes don't communicate about logging

POSIX guarantees that writes up to `PIPE_BUF` (typically 4KB) are atomic. JSON log lines rarely exceed this, so interleaving is prevented at the OS level.

## Usage

### Service Integration

```rust
// In your service's main.rs
fn main() {
    observability::init("daemon");

    tracing::info!("service started");

    // Use structured fields
    tracing::info!(
        user_id = %user.id,
        action = "login",
        "user authenticated"
    );

    // Use spans for context
    let _span = tracing::info_span!("request", request_id = %id).entered();
    tracing::debug!("processing request");
}
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RUST_LOG` | Log level filter | `info` |

Examples:
```bash
RUST_LOG=debug cargo run                    # All debug logs
RUST_LOG=daemon_relay=trace cargo run       # Trace for one module
RUST_LOG=info,daemon_auth=debug cargo run   # Mixed levels
```

### Live Streaming

```bash
# Raw JSONL
tail -f ~/.unbound/logs/dev.jsonl

# Pretty-printed JSON
tail -f ~/.unbound/logs/dev.jsonl | jq

# Filter by service
tail -f ~/.unbound/logs/dev.jsonl | jq 'select(.service == "daemon")'

# Filter by level
tail -f ~/.unbound/logs/dev.jsonl | jq 'select(.level == "ERROR" or .level == "WARN")'

# Filter by target (module)
tail -f ~/.unbound/logs/dev.jsonl | jq 'select(.target | startswith("daemon_relay"))'

# Interactive exploration with lnav
lnav ~/.unbound/logs/dev.jsonl
```

### Human-Readable Output with jq

```bash
# Compact one-liner per log
tail -f ~/.unbound/logs/dev.jsonl | jq -r '"\(.timestamp | split(".")[0]) [\(.level)] \(.service):\(.pid) \(.target) - \(.message)"'

# Output:
# 2024-01-15T10:30:00 [INFO] daemon:12345 daemon_relay::connection - connected to relay
```

## Example Log Output

```json
{"timestamp":"2024-01-15T10:30:00.000001Z","level":"INFO","service":"daemon","pid":12345,"target":"observability","message":"observability initialized","fields":{"log_path":"/Users/you/.unbound/logs/dev.jsonl"}}
{"timestamp":"2024-01-15T10:30:00.000100Z","level":"INFO","service":"daemon","pid":12345,"target":"daemon_bin","message":"daemon starting","fields":{"version":"0.1.0"}}
{"timestamp":"2024-01-15T10:30:00.001000Z","level":"DEBUG","service":"daemon","pid":12345,"target":"daemon_relay::connection","message":"connecting to relay","fields":{"url":"wss://relay.example.com"}}
{"timestamp":"2024-01-15T10:30:00.050000Z","level":"INFO","service":"daemon","pid":12345,"target":"daemon_relay::connection","message":"connected to relay"}
{"timestamp":"2024-01-15T10:30:01.000000Z","level":"INFO","service":"cli","pid":12346,"target":"cli_new","message":"sending command","fields":{"command":"status"},"span":"ipc_request"}
{"timestamp":"2024-01-15T10:30:01.000500Z","level":"DEBUG","service":"daemon","pid":12345,"target":"daemon_ipc","message":"received command","fields":{"command":"status"},"span":"handle_request"}
{"timestamp":"2024-01-15T10:30:01.001000Z","level":"INFO","service":"daemon","pid":12345,"target":"daemon_ipc","message":"responding to status request","span":"handle_request"}
{"timestamp":"2024-01-15T10:30:05.000000Z","level":"WARN","service":"daemon","pid":12345,"target":"daemon_relay::connection","message":"connection lost, reconnecting","fields":{"attempt":1}}
{"timestamp":"2024-01-15T10:30:06.000000Z","level":"ERROR","service":"worker","pid":12347,"target":"worker::task","message":"task failed","fields":{"task_id":"abc123","error":"timeout after 30s"}}
```

## Why This Design?

### Constraint Satisfaction

| Constraint | How It's Satisfied |
|------------|-------------------|
| Services don't expose log commands | `init()` is the only public API; no commands, subscriptions, or endpoints |
| Services don't know about streaming | They write to a layer; the layer writes to a file; file is tailed externally |
| Centralized in observability layer | All logging config lives in this crate; services just call `init()` |
| Single central log stream | All services write to `~/.unbound/logs/dev.jsonl` |
| Live tailing support | File is append-only with per-line flush; standard `tail -f` works |
| Pull-based streaming | Consumers read the file; no push mechanism exists |
| Structured JSONL | Custom `JsonLayer` produces one JSON object per line |
| Multi-process safe | Append-only + flush-per-line + POSIX atomic write guarantees |
| Zero per-service config | `observability::init("name")` — one line, no config files |
| No daemon-specific log commands | Daemon is a pure producer like any other service |
| No log IPC APIs | No IPC; filesystem is the only shared resource |
| No in-memory cross-process channels | File-based; no shared memory or channels |
| No per-service log files | Single file for all services |

### Tradeoffs

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| File vs stdout | File | Enables multi-process aggregation without external tools |
| JSON vs text | JSON | Structured data enables filtering; still readable with `jq` |
| Sync vs async writes | Sync with flush | Simpler; latency is acceptable for dev |
| Single file vs rotation | Single file | Rotation is a future concern; dev logs are transient |

## Future: Production Mode

Production will swap sinks without changing service code:

```rust
// Services still just call:
observability::init("daemon");

// But in prod mode (feature = "prod"), the crate will:
// - Write JSON to stdout (for container log collectors)
// - Send errors to Sentry
// - Emit metrics to Prometheus
```

## Policy Contract

Cross-runtime payload policy, redaction requirements, shared field contract, and release acceptance queries are defined in:

- `docs/observability-policy-contract.md`

Services remain pure producers. The observability crate handles the rest.
