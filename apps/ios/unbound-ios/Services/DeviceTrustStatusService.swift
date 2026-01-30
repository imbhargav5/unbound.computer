//
//  DeviceTrustStatusService.swift
//  unbound-ios
//
//  Service for managing device trust status (simple boolean flag).
//  Separate from the device_trust_graph architecture.
//  Web devices can NEVER be marked as trusted.
//

import Foundation
import Supabase

/// Errors related to device trust status
enum DeviceTrustStatusError: Error, LocalizedError {
    case deviceNotInitialized
    case notAuthenticated
    case cannotTrustWebDevice
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .deviceNotInitialized:
            return "Device identity not initialized"
        case .notAuthenticated:
            return "You must be signed in"
        case .cannotTrustWebDevice:
            return "Web devices cannot be marked as trusted"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

/// Service for managing device trust status
@Observable
final class DeviceTrustStatusService {
    static let shared = DeviceTrustStatusService()

    private let authService = AuthService.shared
    private let deviceTrustService = DeviceTrustService.shared

    // Local trust state
    private(set) var isTrusted: Bool = false
    private(set) var hasSeenTrustPrompt: Bool = false

    private init() {
        loadLocalState()
    }

    // MARK: - Load/Save Local State

    /// Load trust status from UserDefaults
    func loadLocalState() {
        isTrusted = UserDefaults.standard.bool(forKey: "device.isTrusted")
        hasSeenTrustPrompt = UserDefaults.standard.bool(forKey: "device.hasSeenTrustPrompt")
    }

    /// Save trust status to UserDefaults
    private func saveLocalState() {
        UserDefaults.standard.set(isTrusted, forKey: "device.isTrusted")
        UserDefaults.standard.set(hasSeenTrustPrompt, forKey: "device.hasSeenTrustPrompt")
    }

    // MARK: - Trust Status Management

    /// Update trust status locally and in Supabase
    func setTrusted(_ trusted: Bool) async throws {
        guard let deviceId = deviceTrustService.deviceId else {
            throw DeviceTrustStatusError.deviceNotInitialized
        }

        guard authService.authState.isAuthenticated else {
            throw DeviceTrustStatusError.notAuthenticated
        }

        // Update in Supabase (database will enforce web device constraint)
        let updateData = ["is_trusted": trusted]
        let encoder = JSONEncoder()
        let updateJson = try encoder.encode(updateData)

        do {
            try await authService.supabaseClient
                .from("devices")
                .update(updateJson)
                .eq("id", value: deviceId.uuidString)
                .execute()

            // Update local state
            isTrusted = trusted
            saveLocalState()

        } catch {
            throw DeviceTrustStatusError.networkError(error)
        }
    }

    /// Mark that user has seen the trust prompt
    func markTrustPromptSeen() async throws {
        guard let deviceId = deviceTrustService.deviceId else {
            throw DeviceTrustStatusError.deviceNotInitialized
        }

        guard authService.authState.isAuthenticated else {
            throw DeviceTrustStatusError.notAuthenticated
        }

        // Update in Supabase
        let updateData = ["has_seen_trust_prompt": true]
        let encoder = JSONEncoder()
        let updateJson = try encoder.encode(updateData)

        do {
            try await authService.supabaseClient
                .from("devices")
                .update(updateJson)
                .eq("id", value: deviceId.uuidString)
                .execute()

            // Update local state
            hasSeenTrustPrompt = true
            saveLocalState()

        } catch {
            throw DeviceTrustStatusError.networkError(error)
        }
    }

    /// Fetch trust status from Supabase
    func fetchTrustStatus() async throws {
        guard let deviceId = deviceTrustService.deviceId else {
            throw DeviceTrustStatusError.deviceNotInitialized
        }

        guard authService.authState.isAuthenticated else {
            throw DeviceTrustStatusError.notAuthenticated
        }

        struct DeviceTrustStatusResponse: Decodable {
            let isTrusted: Bool
            let hasSeenTrustPrompt: Bool

            enum CodingKeys: String, CodingKey {
                case isTrusted = "is_trusted"
                case hasSeenTrustPrompt = "has_seen_trust_prompt"
            }
        }

        do {
            let response = try await authService.supabaseClient
                .from("devices")
                .select("is_trusted, has_seen_trust_prompt")
                .eq("id", value: deviceId.uuidString)
                .single()
                .execute()

            let decoder = JSONDecoder()
            let status = try decoder.decode(DeviceTrustStatusResponse.self, from: response.data)

            isTrusted = status.isTrusted
            hasSeenTrustPrompt = status.hasSeenTrustPrompt
            saveLocalState()

        } catch {
            throw DeviceTrustStatusError.networkError(error)
        }
    }

    // MARK: - Computed Properties

    /// Whether we should show the trust onboarding screen
    /// Shows on all screens until the device is trusted
    var shouldShowTrustOnboarding: Bool {
        !isTrusted
    }
}
