# observability

Centralized tracing setup for Unbound services.

This crate configures structured JSON logging and ensures every service emits consistent, queryable events without needing to manage sinks directly.

## Design Goals

- Services are **log producers**, not log consumers.
- One config entrypoint for all services.
- Dev mode writes to a shared JSONL file for multi-process streaming.

## Remote Export

The dev subscriber can optionally fan out logs to remote sinks:

- **PostHog** (events for dashboards)
- **Sentry** (error and warning envelopes)

Remote export is configured through `LogConfig` and gated by the runtime
`ObservabilityMode` policy.

## Export Policy Modes

- `DevVerbose` - includes payloads after basic secret redaction.
- `ProdMetadataOnly` - exports metadata only (no raw payloads).

## Dev Mode Output

By default logs are written to:

```
~/.unbound/logs/dev.jsonl
```

You can tail it with:

```bash
tail -f ~/.unbound/logs/dev.jsonl | jq
```

### How to Read Logs in Development Mode

For Claude debug session logs, you can stream a dated session file with:

```bash
tail -n 500 -F ~/.unbound/logs/claude-debug-logs/2026-02-19_a83286a7-2f17-4cda-a547-b92c27516a32.jsonl
```

## Usage

```rust
fn main() {
    observability::init("daemon");
    tracing::info!("ready");
}
```

Advanced configuration:

```rust
observability::init_with_config(observability::LogConfig {
    service_name: "daemon".into(),
    default_level: "debug".into(),
    also_stderr: true,
    mode: observability::ObservabilityMode::DevVerbose,
    ..Default::default()
});
```

## Key Types

- `LogConfig` - service name, level, mode, sinks, sampling
- `ObservabilityMode` - runtime export policy
- `PosthogConfig` - PostHog API key + batching settings
- `SentryConfig` - Sentry DSN
- `SamplingConfig` - per-level sampling rates
- `init` - zero-config setup
- `init_with_config` - fully configurable setup

## Module Layout

```
src/
├── lib.rs       # public API
├── dev.rs       # JSONL file sink
└── json_layer.rs# tracing layer for structured output
```

## Development

```bash
cargo test -p observability
```
