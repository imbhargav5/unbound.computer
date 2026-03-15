# daemon-config-and-utils

Shared config, paths, logging, telemetry, and crypto utilities used across
daemon crates.

## Purpose

This crate holds cross-cutting daemon infrastructure so feature crates can
reuse a single source of truth for runtime configuration and filesystem layout.

## Key Features

- `Config` loading from file + env overrides
- `Paths` helpers for runtime files and app-shared data layout
- Logging and OTEL bootstrap (`init_logging`, `force_flush`, `shutdown`)
- Conversation payload crypto helpers (ChaCha20-Poly1305)
- Device hybrid crypto helpers (X25519 + ChaCha20-Poly1305)
- Telemetry helper utilities (`hash_identifier`, URL host extraction, response summaries)
- Backward-compatible re-export of `git-ops` functions and types

## Configuration

`Config::load(&paths)` loads `config.json` then applies env overrides.

Environment variables:

- `UNBOUND_LOG_LEVEL` (`trace|debug|info|warn|error`)
- `UNBOUND_ENV` (`dev|prod|production`)
- `UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT`
- `UNBOUND_OTEL_HEADERS` (`k=v,k2=v2`)
- `UNBOUND_OTEL_SAMPLER` (`always_on|parentbased_traceidratio`)
- `UNBOUND_OTEL_TRACES_SAMPLER_ARG` (clamped `0.0..1.0`)

## Paths Layout

Default runtime base dir:

- `~/.unbound`

Shared app data dir (default):

- `~/Library/Application Support/com.unbound.macos`

Notable path helpers:

- `socket_file()` -> daemon socket path
- `pid_file()` -> daemon PID path
- `startup_status_file()` -> startup diagnostics JSON
- `database_file()` -> shared SQLite file
- `companies_dir()/company_root()/agent_home_dir()` -> company-agent layout
- `logs_dir()/daemon_log_file()` -> daemon logs

For tests or custom runtime roots, use `Paths::with_base_dir(...)`.

## Conversation Crypto Contract

Helpers:

- `encrypt_conversation_message(...)`
- `encrypt_conversation_message_with_nonce(...)`
- `decrypt_conversation_message(...)`

Contract:

- Key: 32 bytes
- Nonce: 12 bytes
- Cipher: ChaCha20-Poly1305
- Transport fields: base64 strings

## Hybrid Crypto Contract

Helpers:

- `generate_keypair()`
- `encrypt_for_device(...)`
- `decrypt_for_device(...)`

Used for device-scoped secret material exchange.
