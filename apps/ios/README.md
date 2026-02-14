# Unbound iOS App

Native iOS application serving as the trust root for the Unbound platform. Controls Claude Code sessions running on paired Mac devices.

## Prerequisites

- Xcode 15.1+
- iOS 18+ device or simulator
- Apple Developer account (for device deployment)

## Build & Run

```bash
# Open in Xcode
open unbound-ios.xcodeproj

# Build for simulator
xcodebuild build \
  -project unbound-ios.xcodeproj \
  -scheme unbound-ios \
  -configuration Debug \
  -sdk iphonesimulator

# Build for device
xcodebuild build \
  -project unbound-ios.xcodeproj \
  -scheme unbound-ios \
  -configuration Release \
  -sdk iphoneos
```

## Session Detail Preview Fixture

The `SyncedSessionDetailView` canvas preview uses a committed fixture at:

- `unbound-ios/Resources/PreviewFixtures/session-detail-max-messages.json`

Regenerate it from the macOS SQLite database:

```bash
./scripts/export_max_session_fixture.sh
```

Optional arguments:

```bash
./scripts/export_max_session_fixture.sh \
  "/Users/bhargavponnapalli/Library/Application Support/com.unbound.macos/unbound.sqlite" \
  "unbound-ios/Resources/PreviewFixtures/session-detail-max-messages.json"
```

## Bundle Configuration

### Main App

| Setting | Value |
|---------|-------|
| Bundle Identifier | `com.arni.unbound-ios` |
| Development Team | `LLC6TV7P6M` |
| Deployment Target | iOS 18 |
| Swift Version | 5.0 |

### Widget Extension

| Setting | Value |
|---------|-------|
| Bundle Identifier | `com.arni.unbound-ios.UnboundWidget` |
| Display Name | Unbound Widget |
| Extension Point | `com.apple.widgetkit-extension` |

## Environment Variables (Runtime)

Set via Xcode scheme environment or system settings:

| Variable | Debug Default | Release Default |
|----------|---------------|-----------------|
| `RELAY_URL` | `ws://localhost:8080` | `wss://unbound-computer.fly.dev` |
| `API_URL` | `http://localhost:3000` | `https://unbound.computer` |
| `SUPABASE_URL` | `http://127.0.0.1:54321` | (requires configuration) |
| `SUPABASE_PUBLISHABLE_KEY` | Local demo key | (requires configuration) |
| `RECREATE_LOCAL_DB_ON_LAUNCH` | `false` | `false` |

## Local Development Configuration

For easy local configuration, use the xcconfig template:

```bash
# Copy the template
cp Config/Debug.xcconfig.template Config/Debug.xcconfig

# Edit with your local values
open Config/Debug.xcconfig
```

To apply these values in Xcode:

1. Open `unbound-ios.xcodeproj`
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
   - `RECREATE_LOCAL_DB_ON_LAUNCH` = `1` (optional, one-time local SQLite reset)

## Keychain Storage

Service identifier: `com.unbound.ios`

| Key | Purpose |
|-----|---------|
| `com.unbound.device.privateKey` | X25519 private key (32 bytes) |
| `com.unbound.device.publicKey` | X25519 public key (32 bytes) |
| `com.unbound.device.id` | Device UUID |
| `com.unbound.api.key` | API authentication key |
| `com.unbound.trusted.devices` | Trusted devices list (JSON) |

Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

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

## Device Role

This app serves as the **Trust Root**:
- Controls pairing with Mac devices
- Approves web session requests
- Remote control of Claude sessions (pause/resume/stop)
- Views real-time Claude output

## Info.plist Configuration

Add these keys for required permissions:

```xml
<!-- Camera for QR scanning -->
<key>NSCameraUsageDescription</key>
<string>Camera access is needed to scan QR codes for device pairing</string>

<!-- Local network (development) -->
<key>NSLocalNetworkUsageDescription</key>
<string>Local network access for development servers</string>
```

## Core Services

| Service | Purpose |
|---------|---------|
| `KeychainService` | Secure credential storage |
| `CryptoService` | X25519, ECDH, HKDF, ChaCha20-Poly1305 |
| `DeviceTrustService` | Device identity & trusted device management |
| `RelayConnectionService` | WebSocket connection to relay |
| `SessionControlService` | Claude session streaming & control |

## Dependencies

**System Frameworks:**
- Foundation, SwiftUI
- Security (Keychain)
- CryptoKit (encryption)
- AVFoundation (camera/QR scanning)
- Combine (reactive programming)

## Pairing with Mac

1. On Mac: Open Unbound app → Settings → Show QR Code
2. On iOS: Open Unbound app → Devices → Add Device
3. Scan the QR code with camera
4. Confirm pairing on both devices

## Widget Features

The WidgetKit extension provides:
- Live Activity for active Claude sessions
- Dynamic Island integration
- Real-time streaming status

## Production Configuration

For release builds:

1. Configure production Supabase URL in `Config.swift`
2. Set `SUPABASE_PUBLISHABLE_KEY` environment variable
3. Ensure valid provisioning profiles for both app and widget
4. Configure App Store Connect for distribution
