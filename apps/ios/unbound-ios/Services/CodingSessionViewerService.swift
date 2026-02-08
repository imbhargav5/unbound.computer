//
//  CodingSessionViewerService.swift
//  unbound-ios
//
//  Service for iOS devices to join and view coding sessions created on macOS.
//  Handles fetching and decrypting session secrets to enable conversation viewing.
//

import Foundation
import Logging
import Supabase

private let logger = Logger(label: "app.session")

/// Errors when joining a coding session as a viewer
enum CodingSessionViewerError: Error, LocalizedError {
    case notAuthenticated
    case noDeviceId
    case sessionNotFound(UUID)
    case secretNotFound(UUID)
    case decryptionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .noDeviceId:
            return "Device ID not found in keychain"
        case .sessionNotFound(let sessionId):
            return "Coding session not found: \(sessionId)"
        case .secretNotFound(let sessionId):
            return "No encrypted secret found for this device in session: \(sessionId)"
        case .decryptionFailed(let error):
            return "Failed to decrypt session secret: \(error.localizedDescription)"
        }
    }
}

/// Service for viewing coding sessions on iOS
final class CodingSessionViewerService {
    private let sessionSecretService: SessionSecretService
    private let authService: AuthService

    init(
        sessionSecretService: SessionSecretService = .shared,
        authService: AuthService = .shared
    ) {
        self.sessionSecretService = sessionSecretService
        self.authService = authService
    }

    // MARK: - Join Session

    /// Joins a coding session as a viewer by fetching and decrypting the session secret
    ///
    /// This method:
    /// 1. Validates user is authenticated
    /// 2. Fetches device ID from keychain
    /// 3. Fetches encrypted secret from database
    /// 4. Decrypts secret using device private key
    /// 5. Returns decrypted session secret for use in conversation decryption
    ///
    /// - Parameter sessionId: UUID of the coding session to join
    /// - Returns: Decrypted session secret string
    /// - Throws: CodingSessionViewerError if join fails
    func joinCodingSession(_ sessionId: UUID) async throws -> String {
        // 1. Get current user ID
        guard let userIdString = authService.currentUserId,
              let userId = UUID(uuidString: userIdString) else {
            throw CodingSessionViewerError.notAuthenticated
        }

        // 2. Get device ID from keychain
        let keychainService = KeychainService.shared
        guard let deviceId = try? keychainService.getDeviceId(forUser: userIdString) else {
            throw CodingSessionViewerError.noDeviceId
        }

        // 3. Fetch and decrypt session secret
        do {
            let sessionSecret = try await sessionSecretService.fetchAndDecryptCodingSessionSecret(
                sessionId: sessionId,
                deviceId: deviceId,
                userId: userId,
                supabase: authService.supabaseClient
            )

            logger.info("Successfully joined coding session \(sessionId)")
            return sessionSecret

        } catch let sessionError as SessionSecretError {
            switch sessionError {
            case .databaseError:
                throw CodingSessionViewerError.secretNotFound(sessionId)
            default:
                throw CodingSessionViewerError.decryptionFailed(sessionError)
            }
        } catch {
            throw CodingSessionViewerError.decryptionFailed(error)
        }
    }

    // MARK: - Check Session Availability

    /// Checks if a coding session secret is available for this device
    ///
    /// - Parameter sessionId: UUID of the coding session
    /// - Returns: True if secret exists and is accessible, false otherwise
    func isCodingSessionAvailable(_ sessionId: UUID) async -> Bool {
        guard let userIdString = authService.currentUserId,
              let deviceId = try? KeychainService.shared.getDeviceId(forUser: userIdString) else {
            return false
        }

        do {
            let response = try await authService.supabaseClient
                .from("agent_coding_session_secrets")
                .select("id")
                .eq("session_id", value: sessionId.uuidString)
                .eq("device_id", value: deviceId.uuidString)
                .limit(1)
                .execute()

            return response.data.count > 2 // More than just "[]"
        } catch {
            logger.error("Error checking session availability: \(error)")
            return false
        }
    }

    // MARK: - List Available Sessions

    /// Fetches all coding sessions that this device can view
    ///
    /// - Returns: Array of session IDs that have secrets for this device
    func listAvailableCodingSessions() async throws -> [UUID] {
        guard let userIdString = authService.currentUserId,
              let deviceId = try? KeychainService.shared.getDeviceId(forUser: userIdString) else {
            return []
        }

        do {
            let response = try await authService.supabaseClient
                .from("agent_coding_session_secrets")
                .select("session_id")
                .eq("device_id", value: deviceId.uuidString)
                .execute()

            struct SessionRow: Codable {
                let sessionId: String

                enum CodingKeys: String, CodingKey {
                    case sessionId = "session_id"
                }
            }

            let rows = try JSONDecoder().decode([SessionRow].self, from: response.data)
            return rows.compactMap { UUID(uuidString: $0.sessionId) }

        } catch {
            logger.error("Error listing sessions: \(error)")
            return []
        }
    }
}
