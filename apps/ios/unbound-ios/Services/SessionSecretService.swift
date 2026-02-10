//
//  SessionSecretService.swift
//  unbound-ios
//
//  Service for managing coding session secrets and decrypting them for viewers.
//  iOS devices act as viewers and need to decrypt secrets created by macOS executors.
//

import Foundation
import CryptoKit
import Logging
import Security
import Supabase

private let logger = Logger(label: "app.session")

/// Errors for session secret operations
enum SessionSecretError: Error, LocalizedError {
    case invalidPublicKey
    case invalidCiphertext
    case decryptionFailed
    case missingDeviceKey
    case databaseError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidPublicKey:
            return "Invalid ephemeral public key format"
        case .invalidCiphertext:
            return "Invalid encrypted secret format"
        case .decryptionFailed:
            return "Failed to decrypt session secret"
        case .missingDeviceKey:
            return "Device private key not found in Keychain"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        }
    }
}

/// Service for decrypting coding session secrets on viewer devices
final class SessionSecretService {
    static let shared = SessionSecretService()

    private init() {}

    // MARK: - Decryption

    /// Decrypts a coding session secret using the device's private key
    ///
    /// Reverses the hybrid encryption process by computing the shared secret from the
    /// ephemeral public key and device private key, then decrypting with ChaChaPoly.
    ///
    /// - Parameters:
    ///   - ephemeralPublicKey: Base64-encoded ephemeral public key from encryption
    ///   - encryptedSecret: Base64-encoded encrypted data (nonce + ciphertext)
    ///   - sessionId: UUID of the coding session (used as salt in key derivation)
    ///   - userId: User ID to fetch device private key from keychain
    /// - Returns: Decrypted session secret string
    /// - Throws: SessionSecretError if decryption fails
    func decryptCodingSessionSecret(
        ephemeralPublicKey: String,
        encryptedSecret: String,
        sessionId: UUID,
        userId: String
    ) throws -> String {
        // 1. Decode ephemeral public key
        guard let ephemeralPubData = Data(base64Encoded: ephemeralPublicKey),
              ephemeralPubData.count == 32 else {
            throw SessionSecretError.invalidPublicKey
        }

        // 2. Decode encrypted data
        guard let encryptedData = Data(base64Encoded: encryptedSecret),
              encryptedData.count >= 28 else { // 12 (nonce) + 16 (tag) minimum
            throw SessionSecretError.invalidCiphertext
        }

        // 3. Get device private key from keychain
        let keychainService = KeychainService.shared
        guard let devicePrivateKeyData = resolveDevicePrivateKey(forUser: userId, keychainService: keychainService),
              devicePrivateKeyData.count == 32 else {
            throw SessionSecretError.missingDeviceKey
        }

        // 4. Compute shared secret via ECDH
        let devicePrivateKey = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: devicePrivateKeyData
        )
        let ephemeralPublicKeyObj = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: ephemeralPubData
        )
        let sharedSecret = try devicePrivateKey.sharedSecretFromKeyAgreement(
            with: ephemeralPublicKeyObj
        )

        // 5. Derive decryption key using same HKDF parameters as macOS
        let salt = sessionId.uuidString.lowercased().data(using: .utf8)!
        let info = "unbound-session-secret-v1".data(using: .utf8)!
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )

        // 6. Extract nonce and ciphertext+tag
        let nonce = encryptedData.prefix(12)
        let ciphertextWithTag = encryptedData.suffix(from: 12)

        // 7. Split ciphertext and tag (last 16 bytes)
        let tagSize = 16
        guard ciphertextWithTag.count >= tagSize else {
            throw SessionSecretError.decryptionFailed
        }
        let ciphertext = ciphertextWithTag.prefix(ciphertextWithTag.count - tagSize)
        let tag = ciphertextWithTag.suffix(tagSize)

        // 8. Decrypt using ChaChaPoly
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        let decryptedData = try ChaChaPoly.open(sealedBox, using: symmetricKey)

        // 8. Convert to string
        guard let sessionSecret = String(data: decryptedData, encoding: .utf8) else {
            throw SessionSecretError.decryptionFailed
        }

        return sessionSecret
    }

    /// Decrypts a session secret from split nonce + ciphertext envelope fields.
    ///
    /// - Parameters:
    ///   - encapsulationPublicKey: Base64-encoded ephemeral public key
    ///   - nonceB64: Base64-encoded nonce (12 bytes)
    ///   - ciphertextB64: Base64-encoded ciphertext+tag bytes
    ///   - sessionId: UUID of the coding session
    ///   - userId: Authenticated user ID for keychain key lookup
    func decryptCodingSessionSecretEnvelope(
        encapsulationPublicKey: String,
        nonceB64: String,
        ciphertextB64: String,
        sessionId: UUID,
        userId: String
    ) throws -> String {
        guard let nonceData = Data(base64Encoded: nonceB64),
              let ciphertextData = Data(base64Encoded: ciphertextB64) else {
            throw SessionSecretError.invalidCiphertext
        }

        var combined = Data()
        combined.append(nonceData)
        combined.append(ciphertextData)

        return try decryptCodingSessionSecret(
            ephemeralPublicKey: encapsulationPublicKey,
            encryptedSecret: combined.base64EncodedString(),
            sessionId: sessionId,
            userId: userId
        )
    }

    private func resolveDevicePrivateKey(forUser userId: String, keychainService: KeychainService) -> Data? {
        let normalized = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return nil
        }

        var candidates: [String] = [normalized]
        let lowercase = normalized.lowercased()
        if lowercase != normalized {
            candidates.append(lowercase)
        }
        let uppercase = normalized.uppercased()
        if uppercase != normalized && uppercase != lowercase {
            candidates.append(uppercase)
        }
        for candidate in candidates {
            if let key = try? keychainService.getDevicePrivateKey(forUser: candidate) {
                return key
            }
        }
        return nil
    }

    // MARK: - Fetch from Database

    /// Fetches and decrypts a coding session secret from Supabase
    ///
    /// - Parameters:
    ///   - sessionId: UUID of the coding session
    ///   - deviceId: UUID of this device
    ///   - userId: UUID of the current user
    ///   - supabase: Supabase client for database queries
    /// - Returns: Decrypted session secret
    /// - Throws: SessionSecretError if fetch or decryption fails
    func fetchAndDecryptCodingSessionSecret(
        sessionId: UUID,
        deviceId: UUID,
        userId: UUID,
        supabase: SupabaseClient
    ) async throws -> String {
        // 1. Fetch encrypted secret from database
        do {
            let response = try await supabase
                .from("agent_coding_session_secrets")
                .select("ephemeral_public_key, encrypted_secret")
                .eq("session_id", value: sessionId.uuidString)
                .eq("device_id", value: deviceId.uuidString)
                .single()
                .execute()

            struct EncryptedSecretRow: Codable {
                let ephemeralPublicKey: String
                let encryptedSecret: String

                enum CodingKeys: String, CodingKey {
                    case ephemeralPublicKey = "ephemeral_public_key"
                    case encryptedSecret = "encrypted_secret"
                }
            }

            let row = try JSONDecoder().decode(EncryptedSecretRow.self, from: response.data)

            // 2. Decrypt using device private key
            let sessionSecret = try decryptCodingSessionSecret(
                ephemeralPublicKey: row.ephemeralPublicKey,
                encryptedSecret: row.encryptedSecret,
                sessionId: sessionId,
                userId: userId.uuidString
            )

            logger.info("Successfully decrypted coding session secret")
            return sessionSecret

        } catch let decodingError as DecodingError {
            throw SessionSecretError.databaseError(decodingError)
        } catch let sessionError as SessionSecretError {
            throw sessionError
        } catch {
            throw SessionSecretError.databaseError(error)
        }
    }
}
