# daemon-config-and-utils

Shared types, configuration, and utilities used across all daemon crates.

## Purpose

Provides foundational components that other crates depend on, avoiding circular dependencies and code duplication.

## Key Features

- **Configuration**: App config and relay settings
- **Paths**: XDG-compliant directory management
- **Logging**: Unified tracing/logging setup
- **Hybrid crypto**: X25519 + ChaCha20-Poly1305 encryption
- **Git operations**: Status, diff, log, branch management
