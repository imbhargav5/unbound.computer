# observability

Centralized tracing setup for Unbound services.

This crate configures structured JSON logging and ensures every service emits consistent, queryable events without needing to manage sinks directly.

## Design Goals

- Services are **log producers**, not log consumers.
- One config entrypoint for all services.
- Dev mode writes to a shared JSONL file for multi-process streaming.

## Dev Mode Output

By default logs are written to:

```
~/.unbound/logs/dev.jsonl
```

You can tail it with:

```bash
tail -f ~/.unbound/logs/dev.jsonl | jq
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
    ..Default::default()
});
```

## Key Types

- `LogConfig` - service name, default log level, optional log path
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
