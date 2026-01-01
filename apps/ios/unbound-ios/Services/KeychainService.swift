//
//  KeychainService.swift
//  unbound-ios
//
//  Secure key storage using iOS Keychain API for device-rooted trust architecture.
//

import Foundation
import Security

/// Keys used for storing data in the Keychain
enum KeychainKey: String {
    case devicePrivateKey = "com.unbound.device.privateKey"
    case devicePublicKey = "com.unbound.device.publicKey"
    case deviceId = "com.unbound.device.id"
    case apiKey = "com.unbound.api.key"
    case trustedDevices = "com.unbound.trusted.devices"
}

/// Errors that can occur during Keychain operations
enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedData
    case unhandledError(status: OSStatus)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The specified item was not found in the Keychain."
        case .duplicateItem:
            return "An item with the same key already exists."
        case .unexpectedData:
            return "Unexpected data format in Keychain item."
        case .unhandledError(let status):
            return "Keychain error: \(status)"
        case .encodingFailed:
            return "Failed to encode data for Keychain storage."
        case .decodingFailed:
            return "Failed to decode data from Keychain."
        }
    }
}

/// Service for securely storing and retrieving cryptographic keys using iOS Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let accessGroup: String?

    private init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    // MARK: - Generic Keychain Operations

    /// Stores raw data in the Keychain
    func setData(_ data: Data, forKey key: KeychainKey) throws {
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data

        // First try to delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Retrieves raw data from the Keychain
    func getData(forKey key: KeychainKey) throws -> Data {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return data
    }

    /// Stores a string in the Keychain
    func setString(_ string: String, forKey key: KeychainKey) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try setData(data, forKey: key)
    }

    /// Retrieves a string from the Keychain
    func getString(forKey key: KeychainKey) throws -> String {
        let data = try getData(forKey: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    /// Stores a Codable object in the Keychain
    func setObject<T: Encodable>(_ object: T, forKey key: KeychainKey) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(object)
        try setData(data, forKey: key)
    }

    /// Retrieves a Codable object from the Keychain
    func getObject<T: Decodable>(forKey key: KeychainKey) throws -> T {
        let data = try getData(forKey: key)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// Deletes an item from the Keychain
    func delete(forKey key: KeychainKey) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Checks if an item exists in the Keychain
    func exists(forKey key: KeychainKey) -> Bool {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = false

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Clears all items stored by this app in the Keychain
    func clearAll() throws {
        for key in [KeychainKey.devicePrivateKey, .devicePublicKey, .deviceId, .apiKey, .trustedDevices] {
            try? delete(forKey: key)
        }
    }

    // MARK: - Device Identity

    /// Stores the device's private key (32 bytes for X25519)
    func setDevicePrivateKey(_ privateKey: Data) throws {
        guard privateKey.count == 32 else {
            throw KeychainError.unexpectedData
        }
        try setData(privateKey, forKey: .devicePrivateKey)
    }

    /// Retrieves the device's private key
    func getDevicePrivateKey() throws -> Data {
        try getData(forKey: .devicePrivateKey)
    }

    /// Stores the device's public key (32 bytes for X25519)
    func setDevicePublicKey(_ publicKey: Data) throws {
        guard publicKey.count == 32 else {
            throw KeychainError.unexpectedData
        }
        try setData(publicKey, forKey: .devicePublicKey)
    }

    /// Retrieves the device's public key
    func getDevicePublicKey() throws -> Data {
        try getData(forKey: .devicePublicKey)
    }

    /// Stores the device ID
    func setDeviceId(_ deviceId: UUID) throws {
        try setString(deviceId.uuidString, forKey: .deviceId)
    }

    /// Retrieves the device ID
    func getDeviceId() throws -> UUID {
        let idString = try getString(forKey: .deviceId)
        guard let uuid = UUID(uuidString: idString) else {
            throw KeychainError.decodingFailed
        }
        return uuid
    }

    /// Checks if device identity is configured
    var hasDeviceIdentity: Bool {
        exists(forKey: .devicePrivateKey) && exists(forKey: .deviceId)
    }

    // MARK: - API Key

    /// Stores the API key
    func setApiKey(_ apiKey: String) throws {
        try setString(apiKey, forKey: .apiKey)
    }

    /// Retrieves the API key
    func getApiKey() throws -> String {
        try getString(forKey: .apiKey)
    }

    /// Checks if API key is configured
    var hasApiKey: Bool {
        exists(forKey: .apiKey)
    }

    /// Deletes the API key
    func deleteApiKey() throws {
        try delete(forKey: .apiKey)
    }

    // MARK: - Private Helpers

    private func baseQuery(forKey key: KeychainKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unbound.ios",
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}

// MARK: - Convenience Extensions

extension KeychainService {
    /// Safely gets data, returning nil if not found
    func getDataOrNil(forKey key: KeychainKey) -> Data? {
        try? getData(forKey: key)
    }

    /// Safely gets string, returning nil if not found
    func getStringOrNil(forKey key: KeychainKey) -> String? {
        try? getString(forKey: key)
    }

    /// Safely gets object, returning nil if not found
    func getObjectOrNil<T: Decodable>(forKey key: KeychainKey) -> T? {
        try? getObject(forKey: key)
    }
}
