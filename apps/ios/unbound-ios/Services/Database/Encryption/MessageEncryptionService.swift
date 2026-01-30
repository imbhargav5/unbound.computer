//
//  MessageEncryptionService.swift
//  unbound-ios
//
//  Service for encrypting/decrypting message content using ChaCha20-Poly1305.
//  Uses a key derived from the device trust root.
//

import Foundation
import CryptoKit

/// Content type for message content
enum MessageContentType: String, Codable {
    case text
    case image
    case code
    case tool
}

/// Message content structure for encoding/decoding
struct MessageContent: Codable, Equatable, Hashable {
    let type: MessageContentType
    let text: String?
    let imageUrl: String?
    let language: String?
    let toolName: String?
    let toolInput: String?
    let toolOutput: String?

    init(
        type: MessageContentType,
        text: String? = nil,
        imageUrl: String? = nil,
        language: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolOutput: String? = nil
    ) {
        self.type = type
        self.text = text
        self.imageUrl = imageUrl
        self.language = language
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolOutput = toolOutput
    }

    /// Create text content
    static func text(_ content: String) -> MessageContent {
        MessageContent(type: .text, text: content)
    }

    /// Create code content
    static func code(_ content: String, language: String? = nil) -> MessageContent {
        MessageContent(type: .code, text: content, language: language)
    }
}

/// Message role for persistence
enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

/// Service for encrypting/decrypting message content
final class MessageEncryptionService {
    static let shared = MessageEncryptionService()

    private let keychainService: KeychainService
    private let cryptoService: CryptoService
    private var cachedKey: SymmetricKey?

    private init(
        keychainService: KeychainService = .shared,
        cryptoService: CryptoService = .shared
    ) {
        self.keychainService = keychainService
        self.cryptoService = cryptoService
    }

    // MARK: - Encryption Key

    /// Get or derive the database encryption key
    private func getEncryptionKey() throws -> SymmetricKey {
        if let key = cachedKey {
            return key
        }

        // Get device private key from Keychain
        let privateKeyData = try keychainService.getDevicePrivateKey()

        // Derive database encryption key using HKDF
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: privateKeyData),
            salt: Data(),
            info: Data("unbound-database-encryption-v1".utf8),
            outputByteCount: 32
        )

        cachedKey = key
        return key
    }

    // MARK: - Encryption

    /// Encrypt message content array
    /// - Parameter content: Array of MessageContent to encrypt
    /// - Returns: Tuple of (ciphertext, nonce)
    func encrypt(_ content: [MessageContent]) throws -> (ciphertext: Data, nonce: Data) {
        let key = try getEncryptionKey()

        // Encode content to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(content)

        // Encrypt using ChaCha20-Poly1305
        let encrypted = try cryptoService.encrypt(jsonData, using: key)

        return (encrypted.ciphertext, encrypted.nonce)
    }

    /// Decrypt message content from encrypted data
    /// - Parameters:
    ///   - ciphertext: The encrypted data (ciphertext + tag)
    ///   - nonce: The 12-byte nonce used for encryption
    /// - Returns: Array of MessageContent
    func decrypt(ciphertext: Data, nonce: Data) throws -> [MessageContent] {
        let key = try getEncryptionKey()

        let encrypted = EncryptedMessage(nonce: nonce, ciphertext: ciphertext)
        let plaintext = try cryptoService.decrypt(encrypted, using: key)

        // Decode JSON back to content array
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([MessageContent].self, from: plaintext)
    }

    // MARK: - Utility

    /// Check if encryption is available (key exists)
    var isAvailable: Bool {
        keychainService.hasDeviceIdentity
    }

    /// Clear cached encryption key
    func clearCachedKey() {
        cachedKey = nil
    }
}
