# Coding Session Secret Distribution - Integration Guide

This guide explains how to integrate the multi-device session secret distribution feature into your coding session creation flow.

## Overview

When a macOS device creates a coding session, it now automatically encrypts and distributes the session secret to all other registered devices in the user's account. This allows viewer devices (iOS, web, other macs) to decrypt and view the conversation.

## Files Created/Modified

### ✅ New Files
1. **`CodingSessionSecretManager.swift`** - Manages secret distribution
2. **`INTEGRATION_GUIDE.md`** - This file

### ✅ Modified Files
1. **`SessionSecretService.swift`** - Added encryption/decryption methods
2. **Database migration** - Added `ephemeral_public_key` column
3. **`database.types.ts`** - Updated TypeScript types

## Integration Steps

### Step 1: Import the CodingSessionSecretManager

In your session creation code (likely in a ViewModel or Service), add:

```swift
import Foundation

class YourSessionCreationService {
    private let sessionSecretService = SessionSecretService.shared
    private let secretManager = CodingSessionSecretManager()
    private let authService = AuthService.shared

    // ... existing code ...
}
```

### Step 2: Update Session Creation Flow

Find where you create coding sessions and add the secret distribution step. Here's the typical flow:

```swift
func createCodingSession(
    repositoryId: UUID,
    deviceId: UUID
) async throws -> CodingSession {
    // Get current user ID
    guard let userId = authService.currentUser?.id else {
        throw AuthError.noSession
    }

    // 1. Create session record in Supabase
    let sessionId = UUID()
    let session = CodingSession(
        id: sessionId,
        userId: userId,
        deviceId: deviceId,
        repositoryId: repositoryId,
        status: .active,
        // ... other fields ...
    )

    // Insert into Supabase (assuming you have a method for this)
    try await insertSessionToSupabase(session)

    // 2. Generate session secret
    let sessionSecret = sessionSecretService.generateSecret()

    // 3. Store secret in Keychain (existing code)
    try sessionSecretService.storeSecret(sessionSecret, for: sessionId)

    // 4. ✨ NEW: Distribute secret to all user devices
    try await secretManager.distributeSessionSecret(
        sessionId: sessionId,
        sessionSecret: sessionSecret,
        userId: userId,
        executorDeviceId: deviceId
    )

    print("✓ Session created and secrets distributed successfully")

    return session
}
```

### Step 3: Handle Errors Gracefully

Secret distribution failures should NOT fail the entire session creation. Handle them gracefully:

```swift
// 4. Distribute secret to all user devices (non-blocking)
Task {
    do {
        try await secretManager.distributeSessionSecret(
            sessionId: sessionId,
            sessionSecret: sessionSecret,
            userId: userId,
            executorDeviceId: deviceId
        )
    } catch {
        // Log error but don't fail session creation
        print("Warning: Failed to distribute session secrets: \(error)")
        // Optionally: Report to analytics/monitoring
    }
}
```

### Step 4: Test the Integration

1. **Create a session on macOS**
2. **Check database** - Verify `coding_session_secrets` has entries:
   ```sql
   SELECT
     session_id,
     device_id,
     length(ephemeral_public_key) as ephem_key_len,
     length(encrypted_secret) as secret_len
   FROM coding_session_secrets
   WHERE session_id = 'your-session-id';
   ```
3. **Verify encryption** - Each device should have a unique ephemeral key

## Viewer Decryption (iOS/Web)

When a viewer device wants to join a session:

### iOS Example

```swift
class SessionViewerService {
    private let sessionSecretService = SessionSecretService.shared
    private let authService = AuthService.shared

    func joinSession(_ sessionId: UUID) async throws -> String {
        guard let userId = authService.currentUser?.id else {
            throw AuthError.noSession
        }

        // 1. Fetch encrypted secret from database
        let (ephemeralPubKey, encryptedSecret) = try await fetchEncryptedSecret(
            sessionId: sessionId
        )

        // 2. Decrypt using device private key
        let sessionSecret = try sessionSecretService.decryptSecretForDevice(
            ephemeralPublicKey: ephemeralPubKey,
            encryptedSecret: encryptedSecret,
            sessionId: sessionId,
            userId: userId.uuidString
        )

        print("✓ Successfully decrypted session secret")

        return sessionSecret
    }

    private func fetchEncryptedSecret(
        sessionId: UUID
    ) async throws -> (ephemeralPublicKey: String, encryptedSecret: String) {
        let supabase = authService.supabaseClient
        let deviceId = try KeychainService.shared.getDeviceId(
            forUser: authService.currentUser!.id.uuidString
        )

        let response = try await supabase
            .from("coding_session_secrets")
            .select("ephemeral_public_key, encrypted_secret")
            .eq("session_id", value: sessionId.uuidString)
            .eq("device_id", value: deviceId.uuidString)
            .single()
            .execute()

        struct Result: Codable {
            let ephemeralPublicKey: String
            let encryptedSecret: String

            enum CodingKeys: String, CodingKey {
                case ephemeralPublicKey = "ephemeral_public_key"
                case encryptedSecret = "encrypted_secret"
            }
        }

        let result = try JSONDecoder().decode(Result.self, from: response.data)
        return (result.ephemeralPublicKey, result.encryptedSecret)
    }
}
```

### TypeScript/Web Example

```typescript
import { createClient } from '@supabase/supabase-js';
import { decryptSessionSecret } from '@/crypto/session-encryption';

async function joinSession(sessionId: string) {
  const supabase = createClient(/* ... */);
  const deviceId = await getDeviceId();

  // 1. Fetch encrypted secret
  const { data, error } = await supabase
    .from('coding_session_secrets')
    .select('ephemeral_public_key, encrypted_secret')
    .eq('session_id', sessionId)
    .eq('device_id', deviceId)
    .single();

  if (error) throw error;

  // 2. Decrypt using device private key
  const devicePrivateKey = await getDevicePrivateKey();
  const sessionSecret = await decryptSessionSecret({
    ephemeralPublicKey: data.ephemeral_public_key,
    encryptedSecret: data.encrypted_secret,
    sessionId,
    devicePrivateKey
  });

  console.log('✓ Successfully decrypted session secret');
  return sessionSecret;
}
```

## Security Considerations

### ✅ What's Secure
- **End-to-end encryption**: Server never sees plaintext secrets
- **Perfect forward secrecy**: Each encryption uses ephemeral keys
- **Device isolation**: Compromising one device doesn't affect others
- **Session isolation**: Each session uses unique keys

### ⚠️ Important Notes
1. **Device trust**: Only devices with registered public keys receive secrets
2. **Revocation**: Remove `public_key` from database to revoke device access
3. **Key rotation**: Consider periodic rotation of device keypairs
4. **Audit logging**: Consider logging when secrets are accessed

## Troubleshooting

### Problem: No secrets distributed
**Check:**
- Are there other devices with `is_active = true`?
- Do devices have `public_key` set?
- Is the executor device ID correct?

**Query:**
```sql
SELECT id, name, device_type, is_active,
       CASE WHEN public_key IS NULL THEN 'NO KEY' ELSE 'HAS KEY' END as key_status
FROM devices
WHERE user_id = 'your-user-id';
```

### Problem: Decryption fails on viewer
**Check:**
- Does `coding_session_secrets` have an entry for this device?
- Is the `ephemeral_public_key` column populated?
- Does the device have its private key in keychain?

**Query:**
```sql
SELECT * FROM coding_session_secrets
WHERE session_id = 'session-id' AND device_id = 'device-id';
```

### Problem: "Invalid public key" error
**Cause:** Device public key in database is malformed or wrong length

**Fix:**
```swift
// Regenerate device keypair
let privateKey = Curve25519.KeyAgreement.PrivateKey()
let publicKey = privateKey.publicKey

// Store in keychain
try KeychainService.shared.setDevicePrivateKey(
    privateKey.rawRepresentation,
    forUser: userId
)

// Update database
try await supabase
    .from("devices")
    .update(["public_key": publicKey.rawRepresentation.base64EncodedString()])
    .eq("id", value: deviceId.uuidString)
    .execute()
```

## Performance Optimization

### Async Distribution (Recommended)
Don't block session creation on secret distribution:

```swift
// Create session first
let session = try await createSession()

// Distribute secrets asynchronously
Task.detached {
    do {
        try await secretManager.distributeSessionSecret(...)
    } catch {
        print("Background secret distribution failed: \(error)")
    }
}

return session
```

### Batch Insertion
The manager already uses batch insertion for multiple devices:

```swift
// Single INSERT with multiple VALUES
INSERT INTO coding_session_secrets
(session_id, device_id, ephemeral_public_key, encrypted_secret)
VALUES
  (uuid1, device1, key1, secret1),
  (uuid1, device2, key2, secret2),
  (uuid1, device3, key3, secret3);
```

### Caching Device List
Cache the user's device list for 30 seconds to avoid repeated queries:

```swift
private var deviceCache: [UUID: (devices: [DeviceInfo], timestamp: Date)] = [:]

private func fetchUserDevices(userId: UUID, excludingDeviceId: UUID) async throws -> [DeviceInfo] {
    // Check cache
    if let cached = deviceCache[userId],
       Date().timeIntervalSince(cached.timestamp) < 30 {
        return cached.devices
    }

    // Fetch from database
    let devices = try await fetchFromDatabase(...)

    // Update cache
    deviceCache[userId] = (devices, Date())

    return devices
}
```

## Testing Checklist

- [ ] Single device (no other devices) - should not fail
- [ ] Two devices - both should receive secrets
- [ ] Device with no public key - should be skipped gracefully
- [ ] Inactive device - should not receive secret
- [ ] Decryption on viewer device works
- [ ] Session creation doesn't block on distribution
- [ ] Database has correct `ephemeral_public_key` values
- [ ] Encrypted secrets are unique per device

## Next Steps

1. **Add monitoring**: Track distribution success/failure rates
2. **Add retry logic**: Retry failed distributions after N seconds
3. **Add notifications**: Notify viewer devices when new sessions are available
4. **Add revocation**: UI to revoke device access to sessions
5. **Add key rotation**: Periodic device key rotation

---

**Questions?** Check the implementation in:
- `SessionSecretService.swift` - Encryption methods
- `CodingSessionSecretManager.swift` - Distribution logic
- Database migration `add_ephemeral_public_key_to_session_secrets`
