import Foundation
import XCTest

@testable import unbound_ios

final class SessionSecretKeyStoreTests: XCTestCase {
    private let store = SessionSecretKeyStore.shared
    private let keychain = KeychainService.shared

    func testGetPrefersCanonicalOverLegacy() throws {
        let sessionId = UUID()
        let userId = UUID()
        let canonical = canonicalKey(sessionId: sessionId, userId: userId)
        let legacy = legacyKey(sessionId: sessionId)

        try cleanupKeys(canonical: canonical, legacy: legacy)
        defer { try? cleanupKeys(canonical: canonical, legacy: legacy) }

        try keychain.setString("sess_canonical", forScopedKey: canonical)
        try keychain.setString("sess_legacy", forScopedKey: legacy)

        let secret = try store.get(sessionId: sessionId, userId: userId)
        XCTAssertEqual(secret, "sess_canonical")
    }

    func testGetFallsBackToLegacyWhenCanonicalMissing() throws {
        let sessionId = UUID()
        let userId = UUID()
        let canonical = canonicalKey(sessionId: sessionId, userId: userId)
        let legacy = legacyKey(sessionId: sessionId)

        try cleanupKeys(canonical: canonical, legacy: legacy)
        defer { try? cleanupKeys(canonical: canonical, legacy: legacy) }

        try keychain.setString("sess_legacy", forScopedKey: legacy)
        XCTAssertFalse(keychain.exists(forScopedKey: canonical))

        let secret = try store.get(sessionId: sessionId, userId: userId)
        XCTAssertEqual(secret, "sess_legacy")
    }

    func testSetWritesCanonicalKey() throws {
        let sessionId = UUID()
        let userId = UUID()
        let canonical = canonicalKey(sessionId: sessionId, userId: userId)
        let legacy = legacyKey(sessionId: sessionId)

        try cleanupKeys(canonical: canonical, legacy: legacy)
        defer { try? cleanupKeys(canonical: canonical, legacy: legacy) }

        try store.set(secret: "sess_saved", sessionId: sessionId, userId: userId)

        XCTAssertEqual(try keychain.getString(forScopedKey: canonical), "sess_saved")
        XCTAssertFalse(keychain.exists(forScopedKey: legacy))
    }

    func testDeleteRemovesCanonicalAndLegacy() throws {
        let sessionId = UUID()
        let userId = UUID()
        let canonical = canonicalKey(sessionId: sessionId, userId: userId)
        let legacy = legacyKey(sessionId: sessionId)

        try cleanupKeys(canonical: canonical, legacy: legacy)
        defer { try? cleanupKeys(canonical: canonical, legacy: legacy) }

        try keychain.setString("sess_saved", forScopedKey: canonical)
        try keychain.setString("sess_saved_legacy", forScopedKey: legacy)

        try store.delete(sessionId: sessionId, userId: userId)

        XCTAssertFalse(keychain.exists(forScopedKey: canonical))
        XCTAssertFalse(keychain.exists(forScopedKey: legacy))
    }

    private func cleanupKeys(canonical: String, legacy: String) throws {
        try? keychain.delete(forScopedKey: canonical)
        try? keychain.delete(forScopedKey: legacy)
    }

    private func canonicalKey(sessionId: UUID, userId: UUID) -> String {
        "com.unbound.session.secret.\(sessionId.uuidString.lowercased()).\(userId.uuidString.lowercased())"
    }

    private func legacyKey(sessionId: UUID) -> String {
        "com.unbound.session.secret.\(sessionId.uuidString.lowercased())"
    }
}
