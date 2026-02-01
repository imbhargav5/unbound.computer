# daemon-storage

Platform-native secure storage for secrets.

## Purpose

Abstracts OS-specific secret storage (Keychain, Secret Service, Credential Vault) behind a unified interface.

## Key Features

- **macOS**: Keychain Access via security-framework
- **Linux**: Secret Service (GNOME Keyring / KWallet)
- **Windows**: Credential Vault
- **SecretsManager**: High-level API for tokens, keys, and device trust
