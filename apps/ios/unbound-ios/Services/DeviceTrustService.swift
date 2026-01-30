//
//  DeviceTrustService.swift
//  unbound-ios
//
//  Manages trusted device registry and device pairing for the trust-rooted architecture.
//  The iOS device serves as the trust root that introduces and approves other devices.
//

import Foundation
import CryptoKit
import Logging

private let logger = Logger(label: "app.auth")

/// Role of a device in the trust hierarchy
enum DeviceRole: String, Codable {
    case trustRoot = "trust_root"
    case trustedExecutor = "trusted_executor"
    case temporaryViewer = "temporary_viewer"
}

/// Information about a trusted device
struct TrustedDevice: Codable, Identifiable, Hashable {
    let deviceId: String
    let name: String
    let publicKey: String  // Base64-encoded X25519 public key
    let role: DeviceRole
    let trustedAt: Date
    var expiresAt: Date?
    var lastSeenAt: Date?

    var id: String { deviceId }

    /// Whether the device trust has expired
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    /// Whether this device is currently trusted (not expired)
    var isTrusted: Bool {
        !isExpired
    }
}

/// Result of a device pairing operation
struct PairingResult {
    let trustedDevice: TrustedDevice
    let pairwiseSecret: SymmetricKey
}

/// QR code data format for device pairing (v2 protocol)
struct PairingQRData: Codable {
    let version: Int
    let deviceId: String
    let deviceName: String
    let devicePublicKey: String  // Base64-encoded
    let role: DeviceRole
    let timestamp: Date
    let expiresIn: TimeInterval  // QR code validity in seconds

    /// Whether the QR code has expired
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > expiresIn
    }

    /// Create QR data for this device (trust root)
    static func create(
        deviceId: String,
        deviceName: String,
        publicKey: Data,
        expiresIn: TimeInterval = 300  // 5 minutes default
    ) -> PairingQRData {
        PairingQRData(
            version: 2,
            deviceId: deviceId,
            deviceName: deviceName,
            devicePublicKey: publicKey.base64EncodedString(),
            role: .trustRoot,
            timestamp: Date(),
            expiresIn: expiresIn
        )
    }

    /// Encode to JSON string for QR code
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Parse from JSON string
    static func fromJSON(_ json: String) throws -> PairingQRData {
        guard let data = json.data(using: .utf8) else {
            throw DeviceTrustError.invalidQRData
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PairingQRData.self, from: data)
    }
}

/// Errors that can occur during device trust operations
enum DeviceTrustError: Error, LocalizedError {
    case deviceNotInitialized
    case deviceAlreadyTrusted
    case deviceNotFound
    case qrCodeExpired
    case invalidQRData
    case pairingFailed
    case invalidPublicKey
    case trustRevoked

    var errorDescription: String? {
        switch self {
        case .deviceNotInitialized:
            return "Device identity has not been initialized."
        case .deviceAlreadyTrusted:
            return "This device is already trusted."
        case .deviceNotFound:
            return "The specified device was not found in the trust registry."
        case .qrCodeExpired:
            return "The QR code has expired. Please generate a new one."
        case .invalidQRData:
            return "Invalid QR code data format."
        case .pairingFailed:
            return "Device pairing failed."
        case .invalidPublicKey:
            return "Invalid public key format."
        case .trustRevoked:
            return "Trust for this device has been revoked."
        }
    }
}

/// Service for managing device trust relationships
@Observable
final class DeviceTrustService {
    static let shared = DeviceTrustService()

    private let keychainService: KeychainService
    private let cryptoService: CryptoService

    /// Current list of trusted devices
    private(set) var trustedDevices: [TrustedDevice] = []

    /// This device's identity
    private(set) var deviceId: UUID?
    private(set) var deviceName: String = ""

    /// The currently authenticated user ID (required for user-scoped operations)
    private(set) var currentUserId: String?

    /// Whether this device has been initialized as a trust root for the current user
    var isInitialized: Bool {
        guard let userId = currentUserId else { return false }
        return keychainService.hasDeviceIdentity(forUser: userId)
    }

    /// The trust root device (this iOS device)
    var trustRoot: TrustedDevice? {
        trustedDevices.first { $0.role == .trustRoot }
    }

    /// All trusted executor devices (e.g., Macs)
    var trustedExecutors: [TrustedDevice] {
        trustedDevices.filter { $0.role == .trustedExecutor && $0.isTrusted }
    }

    private init(
        keychainService: KeychainService = .shared,
        cryptoService: CryptoService = .shared
    ) {
        self.keychainService = keychainService
        self.cryptoService = cryptoService
    }

    /// Set the current user ID (call this after authentication)
    func setCurrentUser(_ userId: String) {
        let previousUserId = currentUserId
        currentUserId = userId

        // If user changed, reload identity for the new user
        if previousUserId != userId {
            deviceId = nil
            deviceName = ""
            trustedDevices = []

            // Check if we need to migrate legacy global identity
            migrateLegacyIdentityIfNeeded(forUser: userId)

            // Try to load existing identity for this user
            if keychainService.hasDeviceIdentity(forUser: userId) {
                try? loadDeviceIdentity()
            }
        }
    }

    /// Clear the current user (call this on sign out)
    func clearCurrentUser() {
        currentUserId = nil
        deviceId = nil
        deviceName = ""
        trustedDevices = []
    }

    /// Migrate legacy global device identity to user-scoped storage
    private func migrateLegacyIdentityIfNeeded(forUser userId: String) {
        // Check if there's a legacy global identity
        guard keychainService.hasDeviceIdentity else {
            return
        }

        // Check if user already has a user-scoped identity
        if keychainService.hasDeviceIdentity(forUser: userId) {
            // User already has their own identity, just clear the legacy one
            logger.warning("User already has device identity, clearing legacy global identity")
            keychainService.clearLegacyDeviceIdentity()
            return
        }

        // Migrate the legacy identity to the current user
        do {
            let legacyDeviceId = try keychainService.getDeviceId()
            let legacyPrivateKey = try keychainService.getDevicePrivateKey()
            let legacyPublicKey = try keychainService.getDevicePublicKey()

            // Store under user-scoped keys
            try keychainService.setDeviceId(legacyDeviceId, forUser: userId)
            try keychainService.setDevicePrivateKey(legacyPrivateKey, forUser: userId)
            try keychainService.setDevicePublicKey(legacyPublicKey, forUser: userId)

            // Clear the legacy global identity
            keychainService.clearLegacyDeviceIdentity()

            logger.info("Migrated legacy device identity to user: \(userId), deviceId: \(legacyDeviceId)")
        } catch {
            logger.warning("Failed to migrate legacy device identity: \(error)")
        }
    }

    // MARK: - Device Initialization

    /// Initialize this device as a trust root (first-time setup)
    func initializeAsTrustRoot(deviceName: String) throws {
        guard let userId = currentUserId else {
            throw DeviceTrustError.deviceNotInitialized
        }

        // Generate a new key pair
        let keyPair = cryptoService.generateKeyPair()

        // Generate device ID
        let newDeviceId = UUID()

        // Store in Keychain (user-scoped)
        try keychainService.setDevicePrivateKey(keyPair.privateKeyData, forUser: userId)
        try keychainService.setDevicePublicKey(keyPair.publicKeyData, forUser: userId)
        try keychainService.setDeviceId(newDeviceId, forUser: userId)

        self.deviceId = newDeviceId
        self.deviceName = deviceName

        // Add self as trust root
        let trustRootDevice = TrustedDevice(
            deviceId: newDeviceId.uuidString,
            name: deviceName,
            publicKey: keyPair.publicKeyBase64,
            role: .trustRoot,
            trustedAt: Date(),
            expiresAt: nil,  // Trust root never expires
            lastSeenAt: Date()
        )

        try addTrustedDevice(trustRootDevice)

        logger.info("Device initialized as trust root for user: \(userId), deviceId: \(newDeviceId)")
    }

    /// Load existing device identity from Keychain
    func loadDeviceIdentity() throws {
        guard let userId = currentUserId else {
            throw DeviceTrustError.deviceNotInitialized
        }

        guard keychainService.hasDeviceIdentity(forUser: userId) else {
            throw DeviceTrustError.deviceNotInitialized
        }

        self.deviceId = try keychainService.getDeviceId(forUser: userId)
        loadTrustedDevices()

        // Get device name from trust root entry
        if let trustRoot = trustedDevices.first(where: { $0.deviceId == deviceId?.uuidString }) {
            self.deviceName = trustRoot.name
        }

        logger.info("Device identity loaded for user: \(userId), deviceId: \(deviceId?.uuidString ?? "nil")")
    }

    /// Get this device's key pair
    func getDeviceKeyPair() throws -> X25519KeyPair {
        guard let userId = currentUserId else {
            throw DeviceTrustError.deviceNotInitialized
        }
        let privateKeyData = try keychainService.getDevicePrivateKey(forUser: userId)
        return try cryptoService.keyPairFromPrivateKey(privateKeyData)
    }

    // MARK: - QR Code Generation

    /// Generate QR data for pairing with another device
    func generatePairingQRData() throws -> PairingQRData {
        guard let deviceId else {
            throw DeviceTrustError.deviceNotInitialized
        }

        let publicKey = try keychainService.getDevicePublicKey()

        return PairingQRData.create(
            deviceId: deviceId.uuidString,
            deviceName: deviceName,
            publicKey: publicKey
        )
    }

    // MARK: - Device Pairing

    /// Process a scanned QR code from another device (Mac presenting QR)
    func processPairingQR(_ qrData: PairingQRData) throws -> PairingResult {
        // Validate QR code
        guard qrData.version == 2 else {
            throw DeviceTrustError.invalidQRData
        }

        guard !qrData.isExpired else {
            throw DeviceTrustError.qrCodeExpired
        }

        // Check if already trusted
        if trustedDevices.contains(where: { $0.deviceId == qrData.deviceId }) {
            throw DeviceTrustError.deviceAlreadyTrusted
        }

        // Decode their public key
        guard let theirPublicKeyData = Data(base64Encoded: qrData.devicePublicKey) else {
            throw DeviceTrustError.invalidPublicKey
        }

        // Get our key pair
        let myKeyPair = try getDeviceKeyPair()

        // Compute pairwise secret
        let theirPublicKey = try cryptoService.publicKey(from: theirPublicKeyData)
        let pairwiseSecret = try cryptoService.computePairwiseSecret(
            myPrivateKey: myKeyPair.privateKey,
            theirPublicKey: theirPublicKey
        )

        // Create trusted device entry
        let trustedDevice = TrustedDevice(
            deviceId: qrData.deviceId,
            name: qrData.deviceName,
            publicKey: qrData.devicePublicKey,
            role: qrData.role == .trustRoot ? .trustedExecutor : qrData.role,  // Macs become executors
            trustedAt: Date(),
            expiresAt: nil,  // Trusted executors don't expire by default
            lastSeenAt: nil
        )

        // Save to trusted devices
        try addTrustedDevice(trustedDevice)

        return PairingResult(trustedDevice: trustedDevice, pairwiseSecret: pairwiseSecret)
    }

    // MARK: - Trusted Devices Management

    /// Add a device to the trusted devices list
    func addTrustedDevice(_ device: TrustedDevice) throws {
        // Remove any existing entry with the same ID (update case)
        trustedDevices.removeAll { $0.deviceId == device.deviceId }
        trustedDevices.append(device)
        try saveTrustedDevices()
    }

    /// Remove a device from the trusted devices list
    func removeTrustedDevice(deviceId: String) throws -> Bool {
        let initialCount = trustedDevices.count
        trustedDevices.removeAll { $0.deviceId == deviceId }

        if trustedDevices.count < initialCount {
            try saveTrustedDevices()
            return true
        }
        return false
    }

    /// Update a trusted device's last seen timestamp
    func updateLastSeen(deviceId: String) throws {
        guard let index = trustedDevices.firstIndex(where: { $0.deviceId == deviceId }) else {
            return
        }

        var device = trustedDevices[index]
        device.lastSeenAt = Date()
        trustedDevices[index] = device
        try saveTrustedDevices()
    }

    /// Check if a device is trusted
    func isTrusted(deviceId: String) -> Bool {
        guard let device = trustedDevices.first(where: { $0.deviceId == deviceId }) else {
            return false
        }
        return device.isTrusted
    }

    /// Get a trusted device by ID
    func getTrustedDevice(deviceId: String) -> TrustedDevice? {
        trustedDevices.first { $0.deviceId == deviceId }
    }

    /// Revoke trust for a device
    func revokeTrust(deviceId: String, reason: String? = nil) throws {
        _ = try removeTrustedDevice(deviceId: deviceId)
    }

    /// Compute pairwise secret with a trusted device
    func computePairwiseSecret(with deviceId: String) throws -> SymmetricKey {
        guard let device = getTrustedDevice(deviceId: deviceId) else {
            throw DeviceTrustError.deviceNotFound
        }

        guard device.isTrusted else {
            throw DeviceTrustError.trustRevoked
        }

        guard let theirPublicKeyData = Data(base64Encoded: device.publicKey) else {
            throw DeviceTrustError.invalidPublicKey
        }

        let myKeyPair = try getDeviceKeyPair()
        let theirPublicKey = try cryptoService.publicKey(from: theirPublicKeyData)

        return try cryptoService.computePairwiseSecret(
            myPrivateKey: myKeyPair.privateKey,
            theirPublicKey: theirPublicKey
        )
    }

    /// Derive a session key for communication with a trusted device
    func deriveSessionKey(with deviceId: String, sessionId: String) throws -> SymmetricKey {
        let pairwiseSecret = try computePairwiseSecret(with: deviceId)
        return cryptoService.deriveSessionKey(from: pairwiseSecret, sessionId: sessionId)
    }

    // MARK: - Clear All

    /// Clear all device trust data (factory reset)
    func clearAll() throws {
        trustedDevices = []
        deviceId = nil
        deviceName = ""
        try keychainService.clearAll()
    }

    // MARK: - Private Helpers

    private func loadTrustedDevices() {
        if let devices: [TrustedDevice] = keychainService.getObjectOrNil(forKey: .trustedDevices) {
            self.trustedDevices = devices
        }
    }

    private func saveTrustedDevices() throws {
        try keychainService.setObject(trustedDevices, forKey: .trustedDevices)
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

private struct DeviceTrustServiceKey: EnvironmentKey {
    static let defaultValue = DeviceTrustService.shared
}

extension EnvironmentValues {
    var deviceTrustService: DeviceTrustService {
        get { self[DeviceTrustServiceKey.self] }
        set { self[DeviceTrustServiceKey.self] = newValue }
    }
}
