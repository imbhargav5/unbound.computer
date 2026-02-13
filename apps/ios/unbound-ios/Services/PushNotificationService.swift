//
//  PushNotificationService.swift
//  unbound-ios
//
//  Manages APNs push notification registration and token handling.
//  Used for waking the app when phone is locked to receive Live Activity updates.
//

import Foundation
import Logging
import CryptoKit
import UIKit
import UserNotifications
import SwiftUI

private let logger = Logger(label: "app.network")

/// State of push notification registration
enum PushRegistrationState: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional
    case registering
    case registered(token: String)
    case failed(Error)

    static func == (lhs: PushRegistrationState, rhs: PushRegistrationState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown),
             (.notDetermined, .notDetermined),
             (.denied, .denied),
             (.authorized, .authorized),
             (.provisional, .provisional),
             (.registering, .registering):
            return true
        case (.registered(let lToken), .registered(let rToken)):
            return lToken == rToken
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

/// Service for managing push notification registration and tokens
@Observable
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    /// Current registration state
    private(set) var registrationState: PushRegistrationState = .unknown

    /// The current APNs device token (hex-encoded)
    private(set) var deviceToken: String?

    /// Whether push notifications are currently enabled
    var isPushEnabled: Bool {
        if case .registered = registrationState {
            return true
        }
        return false
    }

    /// APNs environment based on build configuration
    var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private let keychainService: KeychainService

    private override init() {
        self.keychainService = KeychainService.shared
        super.init()
        loadCachedToken()
    }

    // MARK: - Public API

    /// Request push notification authorization and register for remote notifications
    @MainActor
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()

        do {
            // Check current authorization status first
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .notDetermined:
                registrationState = .notDetermined
                // Request authorization
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    registrationState = .authorized
                    await registerForRemoteNotifications()
                } else {
                    registrationState = .denied
                }

            case .denied:
                registrationState = .denied

            case .authorized:
                registrationState = .authorized
                await registerForRemoteNotifications()

            case .provisional:
                registrationState = .provisional
                await registerForRemoteNotifications()

            case .ephemeral:
                registrationState = .authorized
                await registerForRemoteNotifications()

            @unknown default:
                registrationState = .unknown
            }
        } catch {
            registrationState = .failed(error)
        }
    }

    /// Register for remote notifications with APNs
    @MainActor
    func registerForRemoteNotifications() async {
        registrationState = .registering
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called when APNs registration succeeds
    func didRegisterForRemoteNotifications(with deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        self.registrationState = .registered(token: tokenString)

        // Cache the token
        cacheToken(tokenString)

        logger.info("APNs registration successful. Token fingerprint: \(redactedFingerprint(tokenString))")

        // Register token with backend
        Task {
            await registerTokenWithBackend(tokenString)
        }
    }

    /// Register the push token with the backend server
    func registerTokenWithBackend(_ token: String) async {
        guard let deviceId = DeviceTrustService.shared.deviceId else {
            logger.warning("Cannot register push token: no device ID")
            return
        }

        do {
            let accessToken = try await AuthService.shared.getAccessToken()

            var request = URLRequest(url: Config.apiURL.appendingPathComponent("/api/v1/mobile/devices/push-token"))
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let body: [String: Any] = [
                "deviceId": deviceId.uuidString,
                "apnsToken": token,
                "apnsEnvironment": apnsEnvironment,
                "pushEnabled": true
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.warning("Invalid response from push token registration")
                return
            }

            if httpResponse.statusCode == 200 {
                logger.info("Push token registered with backend successfully")
            } else {
                logger.error(
                    "Failed to register push token: \(httpResponse.statusCode), response_summary=\(redactedResponseSummary(data))"
                )
            }
        } catch {
            logger.error("Error registering push token with backend: \(error)")
        }
    }

    /// Called when APNs registration fails
    func didFailToRegisterForRemoteNotifications(with error: Error) {
        self.registrationState = .failed(error)
        logger.error("APNs registration failed: \(error.localizedDescription)")
    }

    /// Check if we need to re-register (token may have changed)
    @MainActor
    func checkRegistrationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            // Already authorized, make sure we're registered
            if case .registered = registrationState {
                // Already registered, nothing to do
            } else {
                await registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Token Caching

    private func loadCachedToken() {
        if let token = keychainService.getStringOrNil(forKey: .apnsDeviceToken) {
            self.deviceToken = token
            // Don't set state to registered - we need to verify with the system
        }
    }

    private func cacheToken(_ token: String) {
        try? keychainService.setString(token, forKey: .apnsDeviceToken)
    }

    /// Clear cached token (on logout)
    func clearCachedToken() {
        deviceToken = nil
        registrationState = .unknown
        try? keychainService.delete(forKey: .apnsDeviceToken)
    }

    private func redactedFingerprint(_ rawValue: String) -> String {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    private func redactedResponseSummary(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "bytes=\(data.count),sha256:\(hex)"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Handle different notification types based on payload
        if let notificationType = userInfo["type"] as? String {
            handleNotificationAction(type: notificationType, userInfo: userInfo)
        }

        completionHandler()
    }

    private func handleNotificationAction(type: String, userInfo: [AnyHashable: Any]) {
        switch type {
        case "session_update":
            // Handle session update notification
            if let sessionId = userInfo["session_id"] as? String {
                logger.debug("Received session update for: \(sessionId)")
            }

        case "approval_request":
            // Handle approval request notification
            if let requestId = userInfo["request_id"] as? String {
                logger.debug("Received approval request: \(requestId)")
            }

        default:
            logger.debug("Unknown notification type: \(type)")
        }
    }
}

// MARK: - SwiftUI Environment

private struct PushNotificationServiceKey: EnvironmentKey {
    static let defaultValue = PushNotificationService.shared
}

extension EnvironmentValues {
    var pushNotificationService: PushNotificationService {
        get { self[PushNotificationServiceKey.self] }
        set { self[PushNotificationServiceKey.self] = newValue }
    }
}
