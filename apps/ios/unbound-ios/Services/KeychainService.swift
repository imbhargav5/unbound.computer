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
    // Device Identity (legacy - global, deprecated)
    case devicePrivateKey = "com.unbound.device.privateKey"
    case devicePublicKey = "com.unbound.device.publicKey"
    case deviceId = "com.unbound.device.id"
    case apiKey = "com.unbound.api.key"
    case trustedDevices = "com.unbound.trusted.devices"

    // Supabase auth tokens
    case supabaseAccessToken = "com.unbound.supabase.accessToken"
    case supabaseRefreshToken = "com.unbound.supabase.refreshToken"
    case supabaseUserId = "com.unbound.supabase.userId"
    case supabaseUserEmail = "com.unbound.supabase.userEmail"

    // Push notification tokens
    case apnsDeviceToken = "com.unbound.apns.deviceToken"

    /// Returns a user-scoped version of this key
    func scoped(to userId: String) -> String {
        "\(rawValue).\(userId)"
    }
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
        for key in [KeychainKey.devicePrivateKey, .devicePublicKey, .deviceId, .apiKey, .trustedDevices,
                    .supabaseAccessToken, .supabaseRefreshToken, .supabaseUserId, .supabaseUserEmail] {
            try? delete(forKey: key)
        }
    }

    // MARK: - Supabase Session

    /// Stores Supabase session tokens
    func setSupabaseSession(accessToken: String, refreshToken: String, userId: String, email: String?) throws {
        try setString(accessToken, forKey: .supabaseAccessToken)
        try setString(refreshToken, forKey: .supabaseRefreshToken)
        try setString(userId, forKey: .supabaseUserId)
        if let email {
            try setString(email, forKey: .supabaseUserEmail)
        }
    }

    /// Retrieves Supabase access token
    func getSupabaseAccessToken() throws -> String {
        try getString(forKey: .supabaseAccessToken)
    }

    /// Retrieves Supabase refresh token
    func getSupabaseRefreshToken() throws -> String {
        try getString(forKey: .supabaseRefreshToken)
    }

    /// Retrieves Supabase user ID
    func getSupabaseUserId() throws -> String {
        try getString(forKey: .supabaseUserId)
    }

    /// Retrieves Supabase user email
    func getSupabaseUserEmail() -> String? {
        getStringOrNil(forKey: .supabaseUserEmail)
    }

    /// Checks if Supabase session exists
    var hasSupabaseSession: Bool {
        exists(forKey: .supabaseAccessToken) && exists(forKey: .supabaseRefreshToken)
    }

    /// Clears Supabase session
    func clearSupabaseSession() throws {
        try? delete(forKey: .supabaseAccessToken)
        try? delete(forKey: .supabaseRefreshToken)
        try? delete(forKey: .supabaseUserId)
        try? delete(forKey: .supabaseUserEmail)
    }

    // MARK: - Device Identity (User-Scoped)

    /// Stores the device's private key for a specific user (32 bytes for X25519)
    func setDevicePrivateKey(_ privateKey: Data, forUser userId: String) throws {
        guard privateKey.count == 32 else {
            throw KeychainError.unexpectedData
        }
        try setData(privateKey, forScopedKey: KeychainKey.devicePrivateKey.scoped(to: userId))
    }

    /// Retrieves the device's private key for a specific user
    func getDevicePrivateKey(forUser userId: String) throws -> Data {
        try getData(forScopedKey: KeychainKey.devicePrivateKey.scoped(to: userId))
    }

    /// Stores the device's public key for a specific user (32 bytes for X25519)
    func setDevicePublicKey(_ publicKey: Data, forUser userId: String) throws {
        guard publicKey.count == 32 else {
            throw KeychainError.unexpectedData
        }
        try setData(publicKey, forScopedKey: KeychainKey.devicePublicKey.scoped(to: userId))
    }

    /// Retrieves the device's public key for a specific user
    func getDevicePublicKey(forUser userId: String) throws -> Data {
        try getData(forScopedKey: KeychainKey.devicePublicKey.scoped(to: userId))
    }

    /// Stores the device ID for a specific user
    func setDeviceId(_ deviceId: UUID, forUser userId: String) throws {
        try setString(deviceId.uuidString, forScopedKey: KeychainKey.deviceId.scoped(to: userId))
    }

    /// Retrieves the device ID for a specific user
    func getDeviceId(forUser userId: String) throws -> UUID {
        let idString = try getString(forScopedKey: KeychainKey.deviceId.scoped(to: userId))
        guard let uuid = UUID(uuidString: idString) else {
            throw KeychainError.decodingFailed
        }
        return uuid
    }

    /// Checks if device identity is configured for a specific user
    func hasDeviceIdentity(forUser userId: String) -> Bool {
        exists(forScopedKey: KeychainKey.devicePrivateKey.scoped(to: userId)) &&
        exists(forScopedKey: KeychainKey.deviceId.scoped(to: userId))
    }

    // MARK: - Device Identity (Legacy - Global, Deprecated)

    /// Stores the device's private key (32 bytes for X25519)
    @available(*, deprecated, message: "Use setDevicePrivateKey(_:forUser:) instead")
    func setDevicePrivateKey(_ privateKey: Data) throws {
        guard privateKey.count == 32 else {
            throw KeychainError.unexpectedData
        }
        try setData(privateKey, forKey: .devicePrivateKey)
    }

    /// Retrieves the device's private key
    @available(*, deprecated, message: "Use getDevicePrivateKey(forUser:) instead")
    func getDevicePrivateKey() throws -> Data {
        try getData(forKey: .devicePrivateKey)
    }

    /// Stores the device's public key (32 bytes for X25519)
    @available(*, deprecated, message: "Use setDevicePublicKey(_:forUser:) instead")
    func setDevicePublicKey(_ publicKey: Data) throws {
        guard publicKey.count == 32 else {
            throw KeychainError.unexpectedData
        }
        try setData(publicKey, forKey: .devicePublicKey)
    }

    /// Retrieves the device's public key
    @available(*, deprecated, message: "Use getDevicePublicKey(forUser:) instead")
    func getDevicePublicKey() throws -> Data {
        try getData(forKey: .devicePublicKey)
    }

    /// Stores the device ID
    @available(*, deprecated, message: "Use setDeviceId(_:forUser:) instead")
    func setDeviceId(_ deviceId: UUID) throws {
        try setString(deviceId.uuidString, forKey: .deviceId)
    }

    /// Retrieves the device ID
    @available(*, deprecated, message: "Use getDeviceId(forUser:) instead")
    func getDeviceId() throws -> UUID {
        let idString = try getString(forKey: .deviceId)
        guard let uuid = UUID(uuidString: idString) else {
            throw KeychainError.decodingFailed
        }
        return uuid
    }

    /// Checks if device identity is configured (legacy global)
    @available(*, deprecated, message: "Use hasDeviceIdentity(forUser:) instead")
    var hasDeviceIdentity: Bool {
        exists(forKey: .devicePrivateKey) && exists(forKey: .deviceId)
    }

    /// Clears the legacy global device identity
    func clearLegacyDeviceIdentity() {
        try? delete(forKey: .devicePrivateKey)
        try? delete(forKey: .devicePublicKey)
        try? delete(forKey: .deviceId)
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

    private func baseQuery(forScopedKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.unbound.ios",
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    // MARK: - Scoped Key Operations

    /// Stores raw data for a scoped key
    func setData(_ data: Data, forScopedKey key: String) throws {
        var query = baseQuery(forScopedKey: key)
        query[kSecValueData as String] = data

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Retrieves raw data for a scoped key
    func getData(forScopedKey key: String) throws -> Data {
        var query = baseQuery(forScopedKey: key)
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

    /// Stores a string for a scoped key
    func setString(_ string: String, forScopedKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try setData(data, forScopedKey: key)
    }

    /// Retrieves a string for a scoped key
    func getString(forScopedKey key: String) throws -> String {
        let data = try getData(forScopedKey: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    /// Checks if a scoped key exists
    func exists(forScopedKey key: String) -> Bool {
        var query = baseQuery(forScopedKey: key)
        query[kSecReturnData as String] = false

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
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
