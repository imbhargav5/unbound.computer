# daemon-config-and-utils

Shared types, configuration, and utilities used across all daemon crates.

## Purpose

Provides foundational components that other crates depend on, avoiding circular dependencies and code duplication.

## Key Features

- **Configuration**: app config and runtime settings
- **Web app URL**: compile-time override for daemon web calls (`UNBOUND_WEB_APP_URL`)
- **Paths**: XDG-compliant directory management
- **Logging + tracing**: unified `tracing` and OpenTelemetry setup
- **Presence DO heartbeat**: compile-time envs for presence ingest
- **Conversation crypto**: shared ChaCha20-Poly1305 helpers for message payloads
- **Hybrid crypto**: X25519 + ChaCha20-Poly1305 encryption
- **Git operations**: status, diff, log, branch management

## Conversation Crypto Utility

`conversation_crypto` provides one shared implementation for conversation payload
encryption/decryption, used by both Supabase and Ably message paths.

Public helpers:

- `encrypt_conversation_message(key, plaintext)`
- `encrypt_conversation_message_with_nonce(key, nonce, plaintext)` (test-oriented)
- `decrypt_conversation_message(key, content_encrypted_b64, content_nonce_b64)`

Contract:

- key length: 32 bytes
- nonce length: 12 bytes
- algorithm: ChaCha20-Poly1305
- transport encoding: base64 (`content_encrypted`, `content_nonce`)

## Path Helpers

`Paths` includes socket helpers used by daemon subprocess bridges:

- `socket_file()` -> `~/.unbound/daemon.sock`
- `falco_socket_file()` -> `~/.unbound/falco.sock`
- `nagato_socket_file()` -> `~/.unbound/nagato.sock`

## Observability Configuration

Environment-driven config used by daemon Rust services:

- `UNBOUND_ENV`: `dev` or `prod`
- `UNBOUND_LOG_LEVEL`: `trace|debug|info|warn|error`
- `UNBOUND_LOG_FORMAT`: `pretty|json`
- `UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT`: OTLP traces endpoint
- `UNBOUND_OTEL_HEADERS`: OTLP headers (`k=v,k2=v2`)
- `UNBOUND_OTEL_SAMPLER`: `always_on|parentbased_traceidratio`
- `UNBOUND_OTEL_TRACES_SAMPLER_ARG`: ratio for ratio-based sampling

Notes:

- In `dev`, logs are verbose and include local file output to `~/.unbound/logs/dev.jsonl`.
- In `prod`, logs are lightweight JSON and traces are sampled by configured sampler settings.

## Presence DO Configuration

Compile-time configuration for daemon presence heartbeats:

- `UNBOUND_PRESENCE_DO_HEARTBEAT_URL`: heartbeat ingest endpoint
- `UNBOUND_PRESENCE_DO_TOKEN`: optional bearer token for ingest auth
- `UNBOUND_PRESENCE_DO_TTL_MS`: TTL used by DO payloads (default 12000ms)

## Web App URL Configuration

The daemon reads the web app base URL at build time via `UNBOUND_WEB_APP_URL`.
`compile_time_web_app_url()` trims whitespace, removes trailing slashes, and falls
back to `https://unbound.computer` if the configured value is empty.
