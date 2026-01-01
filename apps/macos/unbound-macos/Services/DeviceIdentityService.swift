//
//  DeviceIdentityService.swift
//  unbound-macos
//
//  Manages device identity, QR code generation for pairing, and trusted device registry.
//  The Mac acts as a "trusted executor" in the device-rooted trust architecture.
//

import Foundation
import CryptoKit
import AppKit
import CoreImage

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

    /// Create QR data for this device (trusted executor)
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
            role: .trustedExecutor,
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
            throw DeviceIdentityError.invalidQRData
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PairingQRData.self, from: data)
    }
}

/// Errors that can occur during device identity operations
enum DeviceIdentityError: Error, LocalizedError {
    case deviceNotInitialized
    case deviceAlreadyTrusted
    case deviceNotFound
    case qrCodeExpired
    case invalidQRData
    case qrGenerationFailed
    case pairingFailed
    case invalidPublicKey
    case trustRevoked
    case noTrustRoot

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
        case .qrGenerationFailed:
            return "Failed to generate QR code."
        case .pairingFailed:
            return "Device pairing failed."
        case .invalidPublicKey:
            return "Invalid public key format."
        case .trustRevoked:
            return "Trust for this device has been revoked."
        case .noTrustRoot:
            return "No trust root device has been paired yet."
        }
    }
}

/// Service for managing device identity and pairing
@Observable
final class DeviceIdentityService {
    static let shared = DeviceIdentityService()

    private let keychainService: KeychainService
    private let cryptoService: CryptoService

    /// Current list of trusted devices
    private(set) var trustedDevices: [TrustedDevice] = []

    /// This device's identity
    private(set) var deviceId: UUID?
    private(set) var deviceName: String = ""

    /// Whether this device has been initialized
    var isInitialized: Bool {
        keychainService.hasDeviceIdentity
    }

    /// Whether this device is paired with a trust root
    var isPaired: Bool {
        trustedDevices.contains { $0.role == .trustRoot && $0.isTrusted }
    }

    /// The trust root device (iPhone)
    var trustRoot: TrustedDevice? {
        trustedDevices.first { $0.role == .trustRoot && $0.isTrusted }
    }

    private init(
        keychainService: KeychainService = .shared,
        cryptoService: CryptoService = .shared
    ) {
        self.keychainService = keychainService
        self.cryptoService = cryptoService
        loadDeviceName()
        loadTrustedDevices()
    }

    // MARK: - Device Initialization

    /// Initialize this device's identity (first-time setup)
    func initializeDevice() throws {
        guard !isInitialized else { return }

        // Generate a new key pair
        let keyPair = cryptoService.generateKeyPair()

        // Generate device ID
        let newDeviceId = UUID()

        // Store in Keychain
        try keychainService.setDevicePrivateKey(keyPair.privateKeyData)
        try keychainService.setDevicePublicKey(keyPair.publicKeyData)
        try keychainService.setDeviceId(newDeviceId)

        self.deviceId = newDeviceId
        loadDeviceName()
    }

    /// Load existing device identity from Keychain
    func loadDeviceIdentity() throws {
        guard keychainService.hasDeviceIdentity else {
            throw DeviceIdentityError.deviceNotInitialized
        }

        self.deviceId = try keychainService.getDeviceId()
        loadDeviceName()
        loadTrustedDevices()
    }

    /// Get this device's key pair
    func getDeviceKeyPair() throws -> X25519KeyPair {
        let privateKeyData = try keychainService.getDevicePrivateKey()
        return try cryptoService.keyPairFromPrivateKey(privateKeyData)
    }

    /// Get this device's public key
    func getDevicePublicKey() throws -> Data {
        try keychainService.getDevicePublicKey()
    }

    // MARK: - QR Code Generation

    /// Generate QR code data for pairing
    func generatePairingQRData() throws -> PairingQRData {
        // Ensure device is initialized
        if !isInitialized {
            try initializeDevice()
        }

        guard let deviceId else {
            throw DeviceIdentityError.deviceNotInitialized
        }

        let publicKey = try keychainService.getDevicePublicKey()

        return PairingQRData.create(
            deviceId: deviceId.uuidString,
            deviceName: deviceName,
            publicKey: publicKey
        )
    }

    /// Generate QR code image for pairing
    func generatePairingQRImage(size: CGSize = CGSize(width: 300, height: 300)) throws -> NSImage {
        let qrData = try generatePairingQRData()
        let jsonString = try qrData.toJSON()

        guard let data = jsonString.data(using: .utf8) else {
            throw DeviceIdentityError.qrGenerationFailed
        }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw DeviceIdentityError.qrGenerationFailed
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")  // High error correction

        guard let ciImage = filter.outputImage else {
            throw DeviceIdentityError.qrGenerationFailed
        }

        // Scale the image
        let scaleX = size.width / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: size)
        nsImage.addRepresentation(rep)

        return nsImage
    }

    // MARK: - Pairing Response

    /// Handle pairing response from trust root (iOS device)
    func handlePairingResponse(
        trustRootId: String,
        trustRootName: String,
        trustRootPublicKey: String
    ) throws {
        // Validate public key
        guard let publicKeyData = Data(base64Encoded: trustRootPublicKey) else {
            throw DeviceIdentityError.invalidPublicKey
        }

        // Verify it's a valid X25519 key
        _ = try cryptoService.publicKey(from: publicKeyData)

        // Create trusted device entry for the trust root
        let trustRootDevice = TrustedDevice(
            deviceId: trustRootId,
            name: trustRootName,
            publicKey: trustRootPublicKey,
            role: .trustRoot,
            trustedAt: Date(),
            expiresAt: nil,  // Trust root never expires
            lastSeenAt: Date()
        )

        try addTrustedDevice(trustRootDevice)
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

    /// Compute pairwise secret with the trust root
    func computePairwiseSecretWithTrustRoot() throws -> SymmetricKey {
        guard let trustRoot else {
            throw DeviceIdentityError.noTrustRoot
        }

        return try computePairwiseSecret(with: trustRoot.deviceId)
    }

    /// Compute pairwise secret with a trusted device
    func computePairwiseSecret(with deviceId: String) throws -> SymmetricKey {
        guard let device = getTrustedDevice(deviceId: deviceId) else {
            throw DeviceIdentityError.deviceNotFound
        }

        guard device.isTrusted else {
            throw DeviceIdentityError.trustRevoked
        }

        guard let theirPublicKeyData = Data(base64Encoded: device.publicKey) else {
            throw DeviceIdentityError.invalidPublicKey
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

    /// Derive a session key for communication with the trust root
    func deriveSessionKeyWithTrustRoot(sessionId: String) throws -> SymmetricKey {
        guard let trustRoot else {
            throw DeviceIdentityError.noTrustRoot
        }
        return try deriveSessionKey(with: trustRoot.deviceId, sessionId: sessionId)
    }

    // MARK: - Clear All

    /// Clear all device identity data (factory reset)
    func clearAll() throws {
        trustedDevices = []
        deviceId = nil
        try keychainService.clearAll()
    }

    // MARK: - Private Helpers

    private func loadDeviceName() {
        deviceName = Host.current().localizedName ?? "Mac"
    }

    private func loadTrustedDevices() {
        if let devices: [TrustedDevice] = keychainService.getObjectOrNil(forKey: .trustedDevices) {
            self.trustedDevices = devices
        }
    }

    private func saveTrustedDevices() throws {
        try keychainService.setObject(trustedDevices, forKey: .trustedDevices)
    }
}
