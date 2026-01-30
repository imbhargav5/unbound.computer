//
//  PairingToken.swift
//  unbound-macos
//
//  Models for QR-based device pairing using Supabase pairing tokens.
//  Simplified flow: macOS creates token, iOS scans and approves, sets verified_at.
//

import Foundation

/// Status of a pairing token
enum PairingTokenStatus: String, Codable {
    case pending    // Token created, waiting for iOS to scan
    case approved   // iOS approved, establishing trust
    case completed  // Pairing successful, trust established
    case expired    // Token exceeded TTL
    case cancelled  // User cancelled pairing
}

/// QR code payload for device pairing (v2 simplified)
struct PairingQRPayload: Codable {
    let version: Int
    let tokenId: String
    let token: String
    let relaySessionId: String
    let deviceName: String
    let expiresAt: Date

    /// Create QR payload for pairing
    static func create(
        tokenId: UUID,
        token: String,
        relaySessionId: UUID,
        deviceName: String,
        expiresAt: Date
    ) -> PairingQRPayload {
        PairingQRPayload(
            version: 2,
            tokenId: tokenId.uuidString,
            token: token,
            relaySessionId: relaySessionId.uuidString,
            deviceName: deviceName,
            expiresAt: expiresAt
        )
    }

    /// Encode to JSON string for QR code
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PairingError.encodingFailed
        }
        return json
    }

    /// Parse from JSON string
    static func fromJSON(_ json: String) throws -> PairingQRPayload {
        guard let data = json.data(using: .utf8) else {
            throw PairingError.invalidQRData
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PairingQRPayload.self, from: data)
    }

    /// Whether the QR code has expired
    var isExpired: Bool {
        Date() > expiresAt
    }
}

/// Pairing token record from Supabase
struct PairingToken: Codable {
    let id: UUID
    let userId: UUID
    let requestingDeviceId: UUID
    let requestingDeviceName: String
    let requestingDeviceType: String
    let token: String
    let expiresAt: Date
    let status: PairingTokenStatus
    let approvingDeviceId: UUID?
    let relaySessionId: UUID?
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case requestingDeviceId = "requesting_device_id"
        case requestingDeviceName = "requesting_device_name"
        case requestingDeviceType = "requesting_device_type"
        case token
        case expiresAt = "expires_at"
        case status
        case approvingDeviceId = "approving_device_id"
        case relaySessionId = "relay_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }
}

/// Result of creating a pairing token
struct PairingTokenResult {
    let token: PairingToken
    let qrPayload: PairingQRPayload
}

/// Errors that can occur during pairing
enum PairingError: Error, LocalizedError {
    case notAuthenticated
    case deviceNotInitialized
    case tokenCreationFailed
    case tokenNotFound
    case tokenExpired
    case invalidQRData
    case encodingFailed
    case qrGenerationFailed
    case pairingFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to pair devices"
        case .deviceNotInitialized:
            return "Device identity not initialized"
        case .tokenCreationFailed:
            return "Failed to create pairing token"
        case .tokenNotFound:
            return "Pairing token not found"
        case .tokenExpired:
            return "This QR code has expired. Please generate a new one."
        case .invalidQRData:
            return "Invalid QR code data"
        case .encodingFailed:
            return "Failed to encode QR code data"
        case .qrGenerationFailed:
            return "Failed to generate QR code image"
        case .pairingFailed(let message):
            return "Pairing failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
