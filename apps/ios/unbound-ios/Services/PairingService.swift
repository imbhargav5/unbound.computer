//
//  PairingService.swift
//  unbound-ios
//
//  Service for approving device pairing via QR code scanning.
//  iOS scans macOS QR code, updates pairing token and sets verified_at on device.
//

import Foundation
import UIKit
import Supabase

@Observable
final class PairingService {
    static let shared = PairingService()

    private(set) var isApproving = false

    private let authService: AuthService

    private init(authService: AuthService = .shared) {
        self.authService = authService
    }

    // MARK: - Approve Pairing

    /// Approve a pairing request from macOS device
    func approvePairing(payload: PairingQRPayload) async throws {
        // Check authentication
        guard authService.authState.isAuthenticated else {
            throw PairingError.notAuthenticated
        }

        guard let userId = authService.currentUserId,
              let currentDeviceId = try? await getCurrentDeviceId() else {
            throw PairingError.deviceNotInitialized
        }

        // Check if expired
        if payload.isExpired {
            throw PairingError.tokenExpired
        }

        isApproving = true
        defer { isApproving = false }

        do {
            // 1. Update pairing token status to approved
            let updatePairingData = [
                "status": "approved",
                "approving_device_id": currentDeviceId.uuidString
            ]

            let encoder = JSONEncoder()
            let updateData = try encoder.encode(updatePairingData)

            try await authService.supabaseClient
                .from("pairing_tokens")
                .update(updateData)
                .eq("id", value: payload.tokenId)
                .execute()

            // 2. Fetch the pairing token to get requesting_device_id
            let tokenResponse = try await authService.supabaseClient
                .from("pairing_tokens")
                .select()
                .eq("id", value: payload.tokenId)
                .single()
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let token = try decoder.decode(PairingToken.self, from: tokenResponse.data)

            // 3. Set verified_at on the requesting device (macOS)
            let verifyDeviceData = [
                "verified_at": ISO8601DateFormatter().string(from: Date())
            ]

            let verifyData = try encoder.encode(verifyDeviceData)

            try await authService.supabaseClient
                .from("devices")
                .update(verifyData)
                .eq("id", value: token.requestingDeviceId.uuidString)
                .execute()

            // 4. Optionally send notification via relay (if relay service exists)
            // try await sendPairingApprovedViaRelay(payload, currentDeviceId: currentDeviceId)

        } catch {
            throw PairingError.networkError(error)
        }
    }

    // MARK: - Private Helpers

    /// Get current device ID (iOS device acting as trust root)
    private func getCurrentDeviceId() async throws -> UUID {
        // Fetch current device from devices table
        guard let userId = authService.currentUserId else {
            throw PairingError.notAuthenticated
        }

        do {
            let response = try await authService.supabaseClient
                .from("devices")
                .select()
                .eq("user_id", value: userId)
                .eq("device_role", value: "trust_root")
                .order("created_at", ascending: false)
                .limit(1)
                .single()
                .execute()

            let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
            guard let idString = json?["id"] as? String,
                  let deviceId = UUID(uuidString: idString) else {
                throw PairingError.deviceNotInitialized
            }

            return deviceId

        } catch {
            throw PairingError.networkError(error)
        }
    }

    /// Send PAIRING_APPROVED message via relay (optional real-time notification)
    private func sendPairingApprovedViaRelay(
        _ payload: PairingQRPayload,
        currentDeviceId: UUID
    ) async throws {
        // This would integrate with RelayConnectionService
        // For now, we'll rely on Supabase Realtime subscriptions
        // The macOS app can subscribe to pairing_tokens table changes
    }
}
