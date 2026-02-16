import Foundation
import Logging

private let presenceTokenLogger = Logger(label: "app.presence.token")

struct PresenceTokenResponse: Decodable {
    let token: String
    let expiresAtMS: Int64
    let userID: String
    let deviceID: String
    let scope: [String]

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAtMS = "expires_at_ms"
        case userID = "user_id"
        case deviceID = "device_id"
        case scope
    }
}

private struct PresenceTokenRequestBody: Encodable {
    let deviceId: String
    let scope: [String]?
}

enum PresenceTokenServiceError: Error, LocalizedError {
    case notAuthenticated
    case invalidDeviceId
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .invalidDeviceId:
            return "Device ID is missing"
        case .requestFailed(let message):
            return "Presence token request failed: \(message)"
        case .invalidResponse:
            return "Presence token response is invalid"
        }
    }
}

struct PresenceTokenService {
    static func fetchToken(
        authService: AuthService = .shared,
        keychainService: KeychainService = .shared
    ) async throws -> PresenceTokenResponse {
        guard let resolvedUserId = authService.currentUserId ?? (try? keychainService.getSupabaseUserId()),
              !resolvedUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PresenceTokenServiceError.notAuthenticated
        }

        let deviceId: UUID
        do {
            deviceId = try keychainService.getDeviceId(forUser: resolvedUserId)
        } catch {
            throw PresenceTokenServiceError.invalidDeviceId
        }

        let accessToken: String
        do {
            accessToken = try await authService.getAccessToken()
        } catch {
            throw PresenceTokenServiceError.notAuthenticated
        }

        var request = URLRequest(url: Config.presenceTokenAuthURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            PresenceTokenRequestBody(deviceId: deviceId.uuidString.lowercased(), scope: nil)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PresenceTokenServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw PresenceTokenServiceError.requestFailed(message)
        }

        do {
            let payload = try JSONDecoder().decode(PresenceTokenResponse.self, from: data)
            if payload.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PresenceTokenServiceError.invalidResponse
            }
            return payload
        } catch {
            presenceTokenLogger.warning("Failed to decode presence token response: \(error.localizedDescription)")
            throw PresenceTokenServiceError.invalidResponse
        }
    }
}
