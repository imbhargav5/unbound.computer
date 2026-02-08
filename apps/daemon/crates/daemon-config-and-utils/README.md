# daemon-config-and-utils

Shared types, configuration, and utilities used across all daemon crates.

## Purpose

Provides foundational components that other crates depend on, avoiding circular dependencies and code duplication.

## Key Features

- **Configuration**: App config and relay settings
- **Paths**: XDG-compliant directory management
- **Logging**: Unified tracing/logging setup
- **Conversation crypto**: shared ChaCha20-Poly1305 helpers for message payloads
- **Hybrid crypto**: X25519 + ChaCha20-Poly1305 encryption
- **Git operations**: Status, diff, log, branch management

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
