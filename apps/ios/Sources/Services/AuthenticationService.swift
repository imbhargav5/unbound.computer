import Foundation
import Security

enum AuthError: LocalizedError {
    case authorizationFailed
    case sessionExpired
    case invalidCredentials
    case keychainError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed:
            return "Failed to authorize web session"
        case .sessionExpired:
            return "Session has expired"
        case .invalidCredentials:
            return "Invalid credentials"
        case .keychainError(let message):
            return "Keychain error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

struct WebSessionInit: Codable {
    let sessionId: String
    let sessionToken: String
    let qrCodeUrl: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionToken = "session_token"
        case qrCodeUrl = "qr_code_url"
    }
}

struct WebSessionStatus: Codable {
    let sessionId: String
    let status: String
    let sessionToken: String?
    let authorizedAt: Date?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status
        case sessionToken = "session_token"
        case authorizedAt = "authorized_at"
        case expiresAt = "expires_at"
    }
}

@MainActor
final class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()

    @Published var isAuthenticated = false
    @Published var deviceToken: String?
    @Published var deviceId: String?
    @Published var accountId: String?

    private let keychainHelper = KeychainHelper.shared

    private init() {
        restoreSession()
    }

    // MARK: - Web Session Flow

    func initWebSession() async throws -> WebSessionInit {
        Config.log("🔐 Initializing web session")

        let url = URL(string: "\(Config.apiURL)/v1/web/sessions/init")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.networkError(URLError(.badServerResponse))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let sessionInit = try decoder.decode(WebSessionInit.self, from: data)

        Config.log("✅ Web session initialized: \(sessionInit.sessionId)")
        return sessionInit
    }

    func waitForAuthorization(sessionId: String) async throws {
        Config.log("⏳ Waiting for authorization: \(sessionId)")

        let url = URL(string: "\(Config.apiURL)/v1/web/sessions/\(sessionId)/status")!

        // Poll every 2 seconds for up to 5 minutes
        for _ in 0..<150 {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw AuthError.networkError(URLError(.badServerResponse))
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let status = try decoder.decode(WebSessionStatus.self, from: data)

            Config.log("📊 Session status: \(status.status)")

            switch status.status {
            case "active":
                guard let token = status.sessionToken else {
                    throw AuthError.invalidCredentials
                }

                // Save credentials
                deviceToken = token
                deviceId = sessionId
                isAuthenticated = true

                // Store in Keychain
                try keychainHelper.save(token: token, key: "deviceToken")
                try keychainHelper.save(token: sessionId, key: "deviceId")

                Config.log("✅ Session authorized successfully")
                return

            case "expired", "revoked":
                throw AuthError.authorizationFailed

            case "pending":
                // Continue polling
                try await Task.sleep(for: .seconds(2))

            default:
                Config.log("⚠️ Unknown status: \(status.status)")
                try await Task.sleep(for: .seconds(2))
            }
        }

        // Timeout after 5 minutes
        throw AuthError.sessionExpired
    }

    // MARK: - Session Management

    func restoreSession() {
        Config.log("🔄 Restoring saved session")

        deviceToken = keychainHelper.load(key: "deviceToken")
        deviceId = keychainHelper.load(key: "deviceId")
        accountId = keychainHelper.load(key: "accountId")

        isAuthenticated = deviceToken != nil && deviceId != nil

        if isAuthenticated {
            Config.log("✅ Session restored successfully")
        } else {
            Config.log("ℹ️ No saved session found")
        }
    }

    func clearSession() {
        Config.log("🗑️ Clearing session")

        deviceToken = nil
        deviceId = nil
        accountId = nil
        isAuthenticated = false

        keychainHelper.delete(key: "deviceToken")
        keychainHelper.delete(key: "deviceId")
        keychainHelper.delete(key: "accountId")

        Config.log("✅ Session cleared")
    }

    func saveAccountId(_ accountId: String) {
        self.accountId = accountId
        try? keychainHelper.save(token: accountId, key: "accountId")
    }
}

// MARK: - Keychain Helper

final class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.unbound.SessionsApp"

    private init() {}

    func save(token: String, key: String) throws {
        let data = token.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw AuthError.keychainError("Failed to save to keychain: \(status)")
        }

        Config.log("🔐 Saved to keychain: \(key)")
    }

    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
        Config.log("🗑️ Deleted from keychain: \(key)")
    }
}
