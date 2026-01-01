//
//  CryptoService.swift
//  unbound-macos
//
//  Cryptographic operations using CryptoKit for X25519 key generation,
//  ECDH key agreement, HKDF key derivation, and ChaCha20-Poly1305 AEAD encryption.
//

import Foundation
import CryptoKit

/// Context strings for HKDF key derivation
enum PairwiseContext: String {
    case session = "unbound-session-v1"
    case message = "unbound-message-v1"
    case webSession = "unbound-web-session-v1"
}

/// Errors that can occur during cryptographic operations
enum CryptoError: Error, LocalizedError {
    case invalidKeySize
    case invalidNonceSize
    case encryptionFailed
    case decryptionFailed
    case keyDerivationFailed
    case invalidPublicKey
    case invalidPrivateKey
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidKeySize:
            return "Invalid key size. Expected 32 bytes."
        case .invalidNonceSize:
            return "Invalid nonce size. Expected 12 bytes for ChaCha20-Poly1305."
        case .encryptionFailed:
            return "Encryption operation failed."
        case .decryptionFailed:
            return "Decryption operation failed."
        case .keyDerivationFailed:
            return "Key derivation failed."
        case .invalidPublicKey:
            return "Invalid public key format."
        case .invalidPrivateKey:
            return "Invalid private key format."
        case .authenticationFailed:
            return "Message authentication failed."
        }
    }
}

/// X25519 key pair for ECDH key agreement
struct X25519KeyPair {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let publicKey: Curve25519.KeyAgreement.PublicKey

    /// Raw 32-byte private key
    var privateKeyData: Data {
        privateKey.rawRepresentation
    }

    /// Raw 32-byte public key
    var publicKeyData: Data {
        publicKey.rawRepresentation
    }

    /// Base64-encoded public key for wire transmission
    var publicKeyBase64: String {
        publicKeyData.base64EncodedString()
    }
}

/// Encrypted message with nonce and ciphertext
struct EncryptedMessage {
    let nonce: Data
    let ciphertext: Data

    /// Combined nonce + ciphertext for transmission
    var combined: Data {
        nonce + ciphertext
    }

    /// Base64-encoded combined data
    var base64: String {
        combined.base64EncodedString()
    }

    /// Parse from combined data (12-byte nonce + ciphertext + 16-byte tag)
    init(combined: Data) throws {
        guard combined.count > 28 else {  // 12 nonce + 16 tag minimum
            throw CryptoError.invalidNonceSize
        }
        self.nonce = combined.prefix(12)
        self.ciphertext = combined.dropFirst(12)
    }

    init(nonce: Data, ciphertext: Data) {
        self.nonce = nonce
        self.ciphertext = ciphertext
    }
}

/// Service for cryptographic operations
final class CryptoService {
    static let shared = CryptoService()

    private init() {}

    // MARK: - Key Generation

    /// Generate a new X25519 key pair
    func generateKeyPair() -> X25519KeyPair {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        return X25519KeyPair(privateKey: privateKey, publicKey: privateKey.publicKey)
    }

    /// Create a key pair from existing private key data
    func keyPairFromPrivateKey(_ privateKeyData: Data) throws -> X25519KeyPair {
        guard privateKeyData.count == 32 else {
            throw CryptoError.invalidPrivateKey
        }
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        return X25519KeyPair(privateKey: privateKey, publicKey: privateKey.publicKey)
    }

    /// Create a public key from raw data
    func publicKey(from data: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        guard data.count == 32 else {
            throw CryptoError.invalidPublicKey
        }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }

    /// Create a public key from Base64 string
    func publicKey(fromBase64 string: String) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let data = Data(base64Encoded: string) else {
            throw CryptoError.invalidPublicKey
        }
        return try publicKey(from: data)
    }

    // MARK: - ECDH Key Agreement

    /// Compute a pairwise shared secret using ECDH
    func computePairwiseSecret(
        myPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        theirPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: theirPublicKey)

        // Derive a 32-byte key using HKDF-SHA256
        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("unbound-pairwise-v1".utf8),
            outputByteCount: 32
        )

        return derivedKey
    }

    /// Compute a pairwise secret from raw key data
    func computePairwiseSecret(
        myPrivateKeyData: Data,
        theirPublicKeyData: Data
    ) throws -> SymmetricKey {
        let myPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: myPrivateKeyData)
        let theirPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirPublicKeyData)
        return try computePairwiseSecret(myPrivateKey: myPrivateKey, theirPublicKey: theirPublicKey)
    }

    // MARK: - Key Derivation

    /// Derive a session key from a pairwise secret
    func deriveSessionKey(
        from pairwiseSecret: SymmetricKey,
        sessionId: String,
        context: PairwiseContext = .session
    ) -> SymmetricKey {
        let info = "\(context.rawValue):\(sessionId)"
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: pairwiseSecret,
            salt: Data(),
            info: Data(info.utf8),
            outputByteCount: 32
        )
    }

    /// Derive a message key for a specific purpose and counter
    func deriveMessageKey(
        from pairwiseSecret: SymmetricKey,
        purpose: String,
        counter: UInt64 = 0
    ) -> SymmetricKey {
        let info = "\(PairwiseContext.message.rawValue):\(purpose):\(counter)"
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: pairwiseSecret,
            salt: Data(),
            info: Data(info.utf8),
            outputByteCount: 32
        )
    }

    /// Derive a web session key for device-to-web communication
    func deriveWebSessionKey(
        myPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        webPublicKey: Curve25519.KeyAgreement.PublicKey,
        sessionId: String
    ) throws -> SymmetricKey {
        let pairwiseSecret = try computePairwiseSecret(
            myPrivateKey: myPrivateKey,
            theirPublicKey: webPublicKey
        )
        return deriveSessionKey(from: pairwiseSecret, sessionId: sessionId, context: .webSession)
    }

    /// Generate a random 256-bit session key
    func generateRandomSessionKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    // MARK: - Encryption (ChaCha20-Poly1305)

    /// Encrypt data using ChaCha20-Poly1305 AEAD
    func encrypt(
        _ plaintext: Data,
        using key: SymmetricKey,
        authenticating additionalData: Data = Data()
    ) throws -> EncryptedMessage {
        let nonce = ChaChaPoly.Nonce()
        let sealedBox = try ChaChaPoly.seal(
            plaintext,
            using: key,
            nonce: nonce,
            authenticating: additionalData
        )
        return EncryptedMessage(
            nonce: Data(nonce),
            ciphertext: sealedBox.ciphertext + sealedBox.tag
        )
    }

    /// Encrypt a string using ChaCha20-Poly1305 AEAD
    func encrypt(
        _ plaintext: String,
        using key: SymmetricKey,
        authenticating additionalData: Data = Data()
    ) throws -> EncryptedMessage {
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.encryptionFailed
        }
        return try encrypt(data, using: key, authenticating: additionalData)
    }

    /// Decrypt data using ChaCha20-Poly1305 AEAD
    func decrypt(
        _ encrypted: EncryptedMessage,
        using key: SymmetricKey,
        authenticating additionalData: Data = Data()
    ) throws -> Data {
        guard encrypted.nonce.count == 12 else {
            throw CryptoError.invalidNonceSize
        }

        let nonce = try ChaChaPoly.Nonce(data: encrypted.nonce)

        // Ciphertext includes the 16-byte tag at the end
        let tagSize = 16
        guard encrypted.ciphertext.count >= tagSize else {
            throw CryptoError.decryptionFailed
        }

        let ciphertext = encrypted.ciphertext.prefix(encrypted.ciphertext.count - tagSize)
        let tag = encrypted.ciphertext.suffix(tagSize)

        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        return try ChaChaPoly.open(sealedBox, using: key, authenticating: additionalData)
    }

    /// Decrypt to a string using ChaCha20-Poly1305 AEAD
    func decryptToString(
        _ encrypted: EncryptedMessage,
        using key: SymmetricKey,
        authenticating additionalData: Data = Data()
    ) throws -> String {
        let data = try decrypt(encrypted, using: key, authenticating: additionalData)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CryptoError.decryptionFailed
        }
        return string
    }

    // MARK: - Utility

    /// Convert symmetric key to raw data
    func keyData(from key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// Create symmetric key from raw data
    func symmetricKey(from data: Data) throws -> SymmetricKey {
        guard data.count == 32 else {
            throw CryptoError.invalidKeySize
        }
        return SymmetricKey(data: data)
    }

    /// Generate cryptographically secure random bytes
    func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// Order device IDs lexicographically (for consistent pairwise key derivation)
    func orderDeviceIds(_ id1: String, _ id2: String) -> (smaller: String, larger: String) {
        id1 < id2 ? (id1, id2) : (id2, id1)
    }
}

// MARK: - SymmetricKey Extension

extension SymmetricKey {
    /// Base64-encoded representation of the key
    var base64: String {
        withUnsafeBytes { Data($0).base64EncodedString() }
    }

    /// Create a symmetric key from Base64 string
    init?(base64: String) {
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            return nil
        }
        self.init(data: data)
    }
}
