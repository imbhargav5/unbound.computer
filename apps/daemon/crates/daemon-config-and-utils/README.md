# daemon-config-and-utils

Shared types, configuration, and utilities used across all daemon crates.

## Purpose

Provides foundational components that other crates depend on, avoiding circular dependencies and code duplication.

## Key Features

- **Configuration**: App config and relay settings
- **Web app URL**: compile-time override for daemon web calls (`UNBOUND_WEB_APP_URL`)
- **Paths**: XDG-compliant directory management
- **Logging**: Unified tracing/logging setup
- **Conversation crypto**: shared ChaCha20-Poly1305 helpers for message payloads
- **Hybrid crypto**: X25519 + ChaCha20-Poly1305 encryption
- **Git operations**: Status, diff, log, branch management
- **Observability**: runtime log policy + PostHog/Sentry configuration

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

Environment-driven config used by the daemon and other Rust services:

- `UNBOUND_OBS_MODE`: `dev` or `prod` (affects remote export payloads)
- `UNBOUND_POSTHOG_API_KEY`: enable PostHog export
- `UNBOUND_POSTHOG_HOST`: override PostHog ingest host
- `UNBOUND_SENTRY_DSN`: enable Sentry export
- `UNBOUND_OBS_DEBUG_SAMPLE_RATE`: debug/trace sampling rate
- `UNBOUND_OBS_INFO_SAMPLE_RATE`: info sampling rate
- `UNBOUND_OBS_WARN_SAMPLE_RATE`: warn sampling rate
- `UNBOUND_OBS_ERROR_SAMPLE_RATE`: error sampling rate

## Web App URL Configuration

The daemon reads the web app base URL at build time via `UNBOUND_WEB_APP_URL`.
`compile_time_web_app_url()` trims whitespace, removes trailing slashes, and falls
back to `https://unbound.computer` if the configured value is empty.
