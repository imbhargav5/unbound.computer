//
//  SessionSecretKeyStore.swift
//  unbound-ios
//
//  Keychain-backed storage for decrypted session secrets.
//

import Foundation

protocol ScopedKeyValueStoring: AnyObject {
    func setString(_ string: String, forScopedKey key: String) throws
    func getString(forScopedKey key: String) throws -> String
    func delete(forScopedKey key: String) throws
}

extension KeychainService: ScopedKeyValueStoring {}

protocol SessionSecretKeyStoring {
    func get(sessionId: UUID, userId: UUID) throws -> String?
    func set(secret: String, sessionId: UUID, userId: UUID) throws
    func delete(sessionId: UUID, userId: UUID) throws
}

final class SessionSecretKeyStore: SessionSecretKeyStoring {
    static let shared = SessionSecretKeyStore()

    private let keychainService: ScopedKeyValueStoring

    init(keychainService: ScopedKeyValueStoring = KeychainService.shared) {
        self.keychainService = keychainService
    }

    func get(sessionId: UUID, userId: UUID) throws -> String? {
        let canonical = Self.canonicalKey(sessionId: sessionId, userId: userId)
        if let secret = try getIfPresent(forScopedKey: canonical), !secret.isEmpty {
            return secret
        }

        let legacy = Self.legacyKey(sessionId: sessionId)
        if let secret = try getIfPresent(forScopedKey: legacy), !secret.isEmpty {
            return secret
        }

        return nil
    }

    func set(secret: String, sessionId: UUID, userId: UUID) throws {
        let canonical = Self.canonicalKey(sessionId: sessionId, userId: userId)
        try keychainService.setString(secret, forScopedKey: canonical)
    }

    func delete(sessionId: UUID, userId: UUID) throws {
        let canonical = Self.canonicalKey(sessionId: sessionId, userId: userId)
        try keychainService.delete(forScopedKey: canonical)

        let legacy = Self.legacyKey(sessionId: sessionId)
        try keychainService.delete(forScopedKey: legacy)
    }

    private func getIfPresent(forScopedKey key: String) throws -> String? {
        do {
            return try keychainService.getString(forScopedKey: key)
        } catch KeychainError.itemNotFound {
            return nil
        } catch {
            throw error
        }
    }

    private static func canonicalKey(sessionId: UUID, userId: UUID) -> String {
        let normalizedSession = sessionId.uuidString.lowercased()
        let normalizedUser = userId.uuidString.lowercased()
        return "com.unbound.session.secret.\(normalizedSession).\(normalizedUser)"
    }

    private static func legacyKey(sessionId: UUID) -> String {
        let normalizedSession = sessionId.uuidString.lowercased()
        return "com.unbound.session.secret.\(normalizedSession)"
    }
}
