# Unbound macOS App

Native macOS application for running Claude Code sessions with remote viewing capabilities.

## Prerequisites

- Xcode 15.1+
- macOS 15.7+ (deployment target)
- Claude CLI installed (`claude` command in PATH)
- Git installed

## Build & Run

```bash
# Open in Xcode
open unbound-macos.xcodeproj

# Or build from command line
xcodebuild -project unbound-macos.xcodeproj \
  -scheme unbound-macos \
  -configuration Debug \
  build
```

## Session Detail Preview Fixture

The `SessionDetailView` canvas preview uses a committed fixture at:

- `unbound-macos/Resources/PreviewFixtures/session-detail-max-messages.json`

Regenerate it from the macOS SQLite database (run from repository root):

```bash
./apps/ios/scripts/export_max_session_fixture.sh \
  "<db-path>" \
  "apps/macos/unbound-macos/Resources/PreviewFixtures/session-detail-max-messages.json"
```

Example with the default local database path:

```bash
./apps/ios/scripts/export_max_session_fixture.sh \
  "$HOME/Library/Application Support/com.unbound.macos/unbound.sqlite" \
  "apps/macos/unbound-macos/Resources/PreviewFixtures/session-detail-max-messages.json"
```

## Bundle Configuration

| Setting | Value |
|---------|-------|
| Bundle Identifier | `com.arni.unbound-macos` |
| Development Team | `LLC6TV7P6M` |
| Code Sign Style | Automatic |
| App Sandbox | Disabled |

## Entitlements

The app requires these entitlements (`unbound-macos.entitlements`):

```xml
com.apple.security.app-sandbox = false
com.apple.security.cs.allow-unsigned-executable-memory = true
```

Sandbox is disabled to allow:
- Shell execution for Claude CLI
- Process spawning
- File system access for git operations

## Environment Variables (Runtime)

Set these to override default URLs. Can be configured in Xcode scheme or system environment.

| Variable | Debug Default | Release Default |
|----------|---------------|-----------------|
| `RELAY_URL` | `ws://localhost:8080` | `wss://unbound-computer.fly.dev` |
| `API_URL` | `http://localhost:3000` | `https://unbound.computer` |
| `SUPABASE_URL` | `http://127.0.0.1:54321` | (requires configuration) |
| `SUPABASE_PUBLISHABLE_KEY` | Local demo key | (requires configuration) |

## Local Development Configuration

For easy local configuration, use the xcconfig template:

```bash
# Copy the template
cp Config/Debug.xcconfig.template Config/Debug.xcconfig

# Edit with your local values
open Config/Debug.xcconfig
```

To apply these values in Xcode:

1. Open `unbound-macos.xcodeproj`
2. Select the project in Navigator
3. Go to **Info** tab > **Configurations**
4. Under **Debug**, set the configuration file to `Config/Debug.xcconfig`

Or set environment variables directly in the scheme:

1. **Product** > **Scheme** > **Edit Scheme...**
2. Select **Run** > **Arguments**
3. Add variables under **Environment Variables**:
   - `RELAY_URL` = `ws://localhost:8080`
   - `API_URL` = `http://localhost:3000`
   - `SUPABASE_URL` = `http://127.0.0.1:54321`

## Keychain Storage

Service identifier: `com.unbound.macos`

Stored keys:
| Key | Purpose |
|-----|---------|
| `com.unbound.device.privateKey` | X25519 private key (32 bytes) |
| `com.unbound.device.publicKey` | X25519 public key (32 bytes) |
| `com.unbound.device.id` | Device UUID |
| `com.unbound.api.key` | API authentication key |
| `com.unbound.trusted.devices` | Trusted devices list (JSON) |

## Cryptographic Configuration

| Algorithm | Purpose |
|-----------|---------|
| X25519 | Key exchange (ECDH) |
| HKDF-SHA256 | Key derivation |
| ChaCha20-Poly1305 | AEAD encryption |

Key derivation contexts:
- `unbound-session-v1` - Session keys
- `unbound-message-v1` - Message encryption
- `unbound-web-session-v1` - Web viewer sessions

## Device Roles

| Role | Description |
|------|-------------|
| `trust_root` | iOS device (controller) |
| `trusted_executor` | Mac device (this app) |
| `temporary_viewer` | Web browser viewers |

## Dependencies

**System Frameworks:**
- Foundation, SwiftUI, AppKit
- CryptoKit (encryption)
- Security (Keychain)
- CoreImage (QR code generation)
- Combine (reactive programming)

**Third-party (Swift Package Manager):**
- SwiftTerm - Terminal emulation

## Pairing with iOS

1. Open the app and go to Settings → Devices
2. Click "Show QR Code"
3. Scan with Unbound iOS app
4. QR code valid for 5 minutes

## External Tools Required

The following must be installed on the system:

1. **Claude CLI** - `claude` command must be in PATH
2. **Git** - For version control operations
3. **Shell** - Uses `/bin/zsh` (falls back to `$SHELL`)

## Production Configuration

For release builds, you must configure:

1. Valid Supabase production URL
2. Supabase anonymous key (via environment or build settings)
3. Valid Apple Developer signing certificate
