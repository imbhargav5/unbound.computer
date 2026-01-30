//
//  CryptoUtils.swift
//  unbound-ios
//
//  Pure utility functions for cryptographic operations.
//  All functions are stateless and deterministic.
//
//  Note: PairwiseContext and CryptoError are defined in CryptoService.swift
//  iOS currently uses ChaCha20-Poly1305 (12-byte nonce), same as macOS
//

import Foundation
import CryptoKit

/// Pure utility functions for cryptographic operations
struct CryptoUtils {

    // MARK: - Validation

    /// Validate key size for symmetric encryption (must be 32 bytes)
    /// - Parameter data: Key data to validate
    /// - Throws: CryptoError.invalidKeySize if not 32 bytes
    static func validateKeySize(_ data: Data) throws {
        guard data.count == 32 else {
            throw CryptoError.invalidKeySize
        }
    }

    /// Validate nonce size for ChaCha20-Poly1305 (must be 12 bytes)
    /// - Parameter data: Nonce data to validate
    /// - Throws: CryptoError.invalidNonceSize if not 12 bytes
    static func validateNonceSize(_ data: Data) throws {
        guard data.count == 12 else {
            throw CryptoError.invalidNonceSize
        }
    }

    /// Validate public key size for X25519 (must be 32 bytes)
    /// - Parameter data: Public key data to validate
    /// - Throws: CryptoError.invalidPublicKey if not 32 bytes
    static func validatePublicKeySize(_ data: Data) throws {
        guard data.count == 32 else {
            throw CryptoError.invalidPublicKey
        }
    }

    /// Validate private key size for X25519 (must be 32 bytes)
    /// - Parameter data: Private key data to validate
    /// - Throws: CryptoError.invalidPrivateKey if not 32 bytes
    static func validatePrivateKeySize(_ data: Data) throws {
        guard data.count == 32 else {
            throw CryptoError.invalidPrivateKey
        }
    }

    // MARK: - Key Derivation Context

    /// Build HKDF info string for key derivation
    /// - Parameters:
    ///   - context: Pairwise context (session, message, webSession)
    ///   - identifier: Session ID or message purpose
    /// - Returns: Info string for HKDF
    static func buildKeyDerivationInfo(context: PairwiseContext, identifier: String) -> String {
        "\(context.rawValue):\(identifier)"
    }

    /// Build HKDF info string for message key derivation
    /// - Parameters:
    ///   - purpose: Message purpose identifier
    ///   - counter: Counter value for key rotation
    /// - Returns: Info string for HKDF
    static func buildMessageKeyInfo(purpose: String, counter: UInt64) -> String {
        "\(PairwiseContext.message.rawValue):\(purpose):\(counter)"
    }

    // MARK: - Device ID Ordering

    /// Order two device IDs lexicographically for consistent pairwise key derivation
    /// Ensures both devices derive the same shared secret regardless of who initiates
    /// - Parameters:
    ///   - id1: First device ID
    ///   - id2: Second device ID
    /// - Returns: Tuple of (smaller, larger) device IDs
    static func orderDeviceIds(_ id1: String, _ id2: String) -> (smaller: String, larger: String) {
        id1 < id2 ? (id1, id2) : (id2, id1)
    }

    // MARK: - Data Conversion

    /// Convert symmetric key to raw data
    /// - Parameter key: Symmetric key
    /// - Returns: Raw 32-byte key data
    static func keyToData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// Convert data to Base64 string
    /// - Parameter data: Binary data
    /// - Returns: Base64-encoded string
    static func dataToBase64(_ data: Data) -> String {
        data.base64EncodedString()
    }

    /// Convert Base64 string to data
    /// - Parameter base64: Base64-encoded string
    /// - Returns: Binary data or nil if invalid
    static func base64ToData(_ base64: String) -> Data? {
        Data(base64Encoded: base64)
    }

    // MARK: - ChaCha20-Poly1305 Helpers

    /// Split ciphertext from ChaCha20-Poly1305 sealed box
    /// Format: [ciphertext][16-byte tag]
    /// - Parameter combined: Combined ciphertext + tag
    /// - Returns: Tuple of (ciphertext, tag)
    /// - Throws: CryptoError.decryptionFailed if data too short
    static func splitCiphertextAndTag(_ combined: Data) throws -> (ciphertext: Data, tag: Data) {
        let tagSize = 16
        guard combined.count >= tagSize else {
            throw CryptoError.decryptionFailed
        }
        let ciphertext = combined.prefix(combined.count - tagSize)
        let tag = combined.suffix(tagSize)
        return (ciphertext, tag)
    }

    /// Combine ciphertext and tag for ChaCha20-Poly1305 sealed box
    /// - Parameters:
    ///   - ciphertext: Encrypted data
    ///   - tag: Authentication tag
    /// - Returns: Combined ciphertext + tag
    static func combineCiphertextAndTag(ciphertext: Data, tag: Data) -> Data {
        ciphertext + tag
    }

    // MARK: - Encrypted Message Helpers

    /// Parse encrypted message from combined data (nonce + ciphertext + tag)
    /// Format: [12-byte nonce][ciphertext][16-byte tag]
    /// - Parameter combined: Combined data
    /// - Returns: Tuple of (nonce, ciphertext)
    /// - Throws: CryptoError.invalidNonceSize if data too short
    static func parseEncryptedMessage(_ combined: Data) throws -> (nonce: Data, ciphertext: Data) {
        guard combined.count > 28 else {  // 12 nonce + 16 tag minimum
            throw CryptoError.invalidNonceSize
        }
        let nonce = combined.prefix(12)
        let ciphertext = combined.dropFirst(12)
        return (nonce, ciphertext)
    }

    /// Combine nonce and ciphertext into encrypted message format
    /// Format: [12-byte nonce][ciphertext][16-byte tag]
    /// - Parameters:
    ///   - nonce: 12-byte nonce
    ///   - ciphertext: Ciphertext with tag appended
    /// - Returns: Combined encrypted message
    static func combineEncryptedMessage(nonce: Data, ciphertext: Data) -> Data {
        nonce + ciphertext
    }

    // MARK: - Hex Encoding

    /// Convert data to hexadecimal string
    /// - Parameter data: Binary data
    /// - Returns: Lowercase hex string
    static func dataToHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Convert hexadecimal string to data
    /// - Parameter hex: Hex string (case insensitive)
    /// - Returns: Binary data or nil if invalid
    static func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var hex = hex

        // Remove any whitespace or common prefixes
        hex = hex.replacingOccurrences(of: " ", with: "")
        hex = hex.replacingOccurrences(of: "0x", with: "")

        // Hex string must have even length
        guard hex.count % 2 == 0 else { return nil }

        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        return data
    }
}
