//
//  AuthService.swift
//  unbound-ios
//
//  Supabase authentication service for iOS app.
//  Handles email/password, OAuth, and session management.
//

import Foundation
import Logging
import UIKit
import Supabase
import Auth

private let logger = Logger(label: "app.auth")

/// Authentication state for the app
enum AuthState: Equatable {
    case unknown
    case unauthenticated
    case authenticating
    case validatingSession
    case authenticated(userId: String)
    case error(String)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var isLoading: Bool {
        self == .authenticating || self == .unknown || self == .validatingSession
    }
}

/// OAuth providers supported for authentication
enum OAuthProvider: String, CaseIterable {
    case github
    case google

    var supabaseProvider: Auth.Provider {
        switch self {
        case .github: return .github
        case .google: return .google
        }
    }

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .google: return "Google"
        }
    }

    var iconName: String {
        switch self {
        case .github: return "arrow.triangle.branch"
        case .google: return "globe"
        }
    }
}

/// Errors that can occur during authentication
enum AuthError: Error, LocalizedError {
    case invalidCredentials
    case emailNotConfirmed
    case networkError
    case sessionExpired
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password."
        case .emailNotConfirmed:
            return "Please confirm your email address."
        case .networkError:
            return "Network error. Please check your connection."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .unknown(let message):
            return message
        }
    }
}

/// Service for managing Supabase authentication
@Observable
final class AuthService {
    static let shared = AuthService()

    // MARK: - Properties

    private(set) var authState: AuthState = .unknown
    private(set) var currentUserId: String?
    private(set) var currentUserEmail: String?

    private let _supabaseClient: SupabaseClient
    private let keychainService: KeychainService
    private let deviceTrustService: DeviceTrustService
    private var authStateTask: Task<Void, Never>?
    private var isRegisteringDevice = false

    /// Access to Supabase client for other services
    var supabaseClient: SupabaseClient {
        _supabaseClient
    }

    // MARK: - Initialization

    private init(
        keychainService: KeychainService = .shared,
        deviceTrustService: DeviceTrustService = .shared
    ) {
        self.keychainService = keychainService
        self.deviceTrustService = deviceTrustService
        self._supabaseClient = SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabasePublishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: Config.oauthRedirectURL,
                    flowType: .pkce,
                    // Opt-in to new session behavior per https://github.com/supabase/supabase-swift/pull/822
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // MARK: - Session Management

    /// Loads existing session from Keychain on app launch
    func loadSession() async {
        authState = .unknown

        // Check if we have stored tokens
        guard keychainService.hasSupabaseSession else {
            authState = .unauthenticated
            return
        }

        do {
            // Try to get the current session from Supabase (local cache only)
            let session = try await supabaseClient.auth.session

            // Validate the session against the server
            authState = .validatingSession
            do {
                _ = try await supabaseClient.auth.user()
                handleSession(session)
            } catch let error as Auth.AuthError {
                // Server rejected the token (revoked, banned, expired)
                logger.warning("Server rejected session: \(error)")
                do {
                    let refreshedSession = try await supabaseClient.auth.refreshSession()
                    handleSession(refreshedSession)
                } catch {
                    logger.warning("Session refresh also failed: \(error)")
                    try? keychainService.clearSupabaseSession()
                    authState = .unauthenticated
                }
            } catch {
                // Network failure or other non-auth error — allow cached session for offline support
                logger.info("Server validation unavailable (offline?), using cached session")
                handleSession(session)
            }
        } catch {
            // No valid local session, try to refresh
            do {
                let session = try await supabaseClient.auth.refreshSession()
                handleSession(session)
            } catch {
                // Refresh failed, clear stored tokens
                try? keychainService.clearSupabaseSession()
                authState = .unauthenticated
            }
        }
    }

    /// Starts listening for auth state changes
    func startListening() {
        authStateTask?.cancel()
        authStateTask = Task { [weak self] in
            guard let self else { return }

            for await (event, session) in supabaseClient.auth.authStateChanges {
                await MainActor.run {
                    self.handleAuthStateChange(event: event, session: session)
                }
            }
        }
    }

    /// Stops listening for auth state changes
    func stopListening() {
        authStateTask?.cancel()
        authStateTask = nil
    }

    // MARK: - Email/Password Authentication

    /// Signs up a new user with email and password
    func signUpWithEmail(email: String, password: String) async throws {
        authState = .authenticating

        do {
            let response = try await supabaseClient.auth.signUp(
                email: email,
                password: password
            )

            if let session = response.session {
                handleSession(session)
            } else {
                // Email confirmation required
                authState = .unauthenticated
                throw AuthError.emailNotConfirmed
            }
        } catch let error as AuthError {
            authState = .error(error.localizedDescription)
            throw error
        } catch {
            let authError = mapError(error)
            authState = .error(authError.localizedDescription)
            throw authError
        }
    }

    /// Signs in an existing user with email and password
    func signInWithEmail(email: String, password: String) async throws {
        authState = .authenticating

        do {
            let session = try await supabaseClient.auth.signIn(
                email: email,
                password: password
            )
            handleSession(session)
        } catch {
            let authError = mapError(error)
            authState = .error(authError.localizedDescription)
            throw authError
        }
    }

    // MARK: - Magic Link Authentication

    /// Sends a magic link to the user's email for passwordless sign-in
    func signInWithMagicLink(email: String) async throws {
        authState = .authenticating

        do {
            try await supabaseClient.auth.signInWithOTP(
                email: email,
                redirectTo: Config.oauthRedirectURL
            )
            // Magic link sent successfully - user needs to check email
            authState = .unauthenticated
        } catch {
            let authError = mapError(error)
            authState = .error(authError.localizedDescription)
            throw authError
        }
    }

    // MARK: - Password Reset

    /// Sends a password reset link to the user's email
    func resetPassword(email: String) async throws {
        do {
            try await supabaseClient.auth.resetPasswordForEmail(
                email,
                redirectTo: Config.oauthRedirectURL
            )
            // Reset email sent successfully
        } catch {
            let authError = mapError(error)
            throw authError
        }
    }

    // MARK: - OAuth Authentication

    /// Initiates OAuth sign-in flow
    func signInWithOAuth(provider: OAuthProvider) async throws -> URL {
        authState = .authenticating

        do {
            let url = try await supabaseClient.auth.getOAuthSignInURL(
                provider: provider.supabaseProvider,
                redirectTo: Config.oauthRedirectURL
            )
            return url
        } catch {
            let authError = mapError(error)
            authState = .error(authError.localizedDescription)
            throw authError
        }
    }

    /// Handles OAuth callback URL
    func handleOAuthCallback(url: URL) async throws {
        authState = .authenticating

        do {
            let session = try await supabaseClient.auth.session(from: url)
            handleSession(session)
        } catch {
            let authError = mapError(error)
            authState = .error(authError.localizedDescription)
            throw authError
        }
    }

    // MARK: - Sign Out

    /// Signs out the current user
    func signOut() async throws {
        // Stop presence service
        DevicePresenceService.shared.stop()

        do {
            try await supabaseClient.auth.signOut()
        } catch {
            // Continue with local cleanup even if remote signout fails
            logger.warning("Remote signout failed: \(error)")
        }

        // Clear local state
        try? keychainService.clearSupabaseSession()
        currentUserId = nil
        currentUserEmail = nil
        authState = .unauthenticated
        deviceTrustService.clearCurrentUser()
    }

    // MARK: - Token Access

    /// Gets the current access token for API calls
    func getAccessToken() async throws -> String {
        // First try to get fresh session
        do {
            let session = try await supabaseClient.auth.session
            return session.accessToken
        } catch {
            // Try to refresh
            let session = try await supabaseClient.auth.refreshSession()
            return session.accessToken
        }
    }

    // MARK: - Validation Helpers

    /// Validates email format
    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    // MARK: - Private Helpers

    private func handleSession(_ session: Session) {
        currentUserId = session.user.id.uuidString.lowercased()
        currentUserEmail = session.user.email

        // Store tokens in Keychain
        do {
            try keychainService.setSupabaseSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                userId: session.user.id.uuidString.lowercased(),
                email: session.user.email
            )
        } catch {
            logger.error("Failed to save session to Keychain: \(error)")
        }

        authState = .authenticated(userId: session.user.id.uuidString.lowercased())

        // Register device in Supabase
        Task {
            await registerDevice()
        }
    }

    // MARK: - Device Registration

    /// Register this device in Supabase after authentication
    @MainActor
    func registerDevice() async {
        if isRegisteringDevice {
            logger.debug("Skipping duplicate device registration request while another one is in progress")
            return
        }
        isRegisteringDevice = true
        defer { isRegisteringDevice = false }

        // Set the current user on the device trust service
        guard let userId = currentUserId else {
            logger.warning("Cannot register device: no current user")
            return
        }
        deviceTrustService.setCurrentUser(userId)

        // Initialize device identity for this user if not already done
        if !deviceTrustService.isInitialized {
            do {
                let deviceName = UIDevice.current.name
                try deviceTrustService.initializeAsTrustRoot(deviceName: deviceName)
                logger.info("Device identity created for user: \(userId)")
            } catch {
                logger.error("Failed to initialize device identity: \(error)")
                return
            }
        }

        guard let deviceId = deviceTrustService.deviceId else {
            logger.warning("Cannot register device: missing deviceId")
            return
        }
        let normalizedDeviceId = deviceId.uuidString.lowercased()
        if DevicePresenceService.shared.isRunning(deviceId: normalizedDeviceId, userId: userId) {
            logger.debug("Skipping duplicate device registration for \(normalizedDeviceId)")
            return
        }

        // Determine device type based on idiom
        let deviceType: String
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            deviceType = "ios-tablet"
        default:
            deviceType = "ios-phone"
        }

        // Check local trust status (defaults to false for new devices)
        let isTrusted = UserDefaults.standard.bool(forKey: "device.isTrusted")
        let hasSeenTrustPrompt = UserDefaults.standard.bool(forKey: "device.hasSeenTrustPrompt")

        // Get public key (base64 encoded)
        var publicKeyBase64: String?
        if let publicKeyData = try? keychainService.getDevicePublicKey(forUser: userId) {
            publicKeyBase64 = publicKeyData.base64EncodedString()
        }

        let device = DeviceRegistration(
            id: normalizedDeviceId,
            userId: userId,
            name: deviceTrustService.deviceName,
            deviceType: deviceType,
            hostname: UIDevice.current.name,
            isActive: true,
            lastSeenAt: ISO8601DateFormatter().string(from: Date()),
            isTrusted: isTrusted,
            hasSeenTrustPrompt: hasSeenTrustPrompt,
            publicKey: publicKeyBase64
        )

        do {
            try await supabaseClient
                .from("devices")
                .upsert(device, onConflict: "id")
                .execute()

            logger.info("Device registered: \(device.name) (\(device.id))")

            // Start presence service with Realtime subscription
            DevicePresenceService.shared.start(
                supabase: supabaseClient,
                deviceId: normalizedDeviceId,
                userId: userId
            )
        } catch {
            logger.error("Failed to register device: \(error)")
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession:
            if let session {
                handleSession(session)
            } else {
                authState = .unauthenticated
            }

        case .signedIn:
            if let session {
                handleSession(session)
            }

        case .signedOut:
            try? keychainService.clearSupabaseSession()
            currentUserId = nil
            currentUserEmail = nil
            authState = .unauthenticated
            deviceTrustService.clearCurrentUser()

        case .tokenRefreshed:
            if let session {
                handleSession(session)
            }

        case .userUpdated:
            if let session {
                currentUserEmail = session.user.email
            }

        case .passwordRecovery:
            break

        case .mfaChallengeVerified:
            break

        case .userDeleted:
            try? keychainService.clearSupabaseSession()
            currentUserId = nil
            currentUserEmail = nil
            authState = .unauthenticated
            deviceTrustService.clearCurrentUser()
        }
    }

    private func mapError(_ error: Error) -> AuthError {
        let message = error.localizedDescription.lowercased()

        if message.contains("invalid") || message.contains("credentials") {
            return .invalidCredentials
        } else if message.contains("confirm") || message.contains("verification") {
            return .emailNotConfirmed
        } else if message.contains("network") || message.contains("connection") {
            return .networkError
        } else if message.contains("expired") || message.contains("refresh") {
            return .sessionExpired
        } else {
            return .unknown(error.localizedDescription)
        }
    }
}

// MARK: - SwiftUI Environment

import SwiftUI

private struct AuthServiceKey: EnvironmentKey {
    static let defaultValue = AuthService.shared
}

extension EnvironmentValues {
    var authService: AuthService {
        get { self[AuthServiceKey.self] }
        set { self[AuthServiceKey.self] = newValue }
    }
}

// MARK: - Device Registration Model

private struct DeviceRegistration: Encodable {
    let id: String
    let userId: String
    let name: String
    let deviceType: String
    let hostname: String
    let isActive: Bool
    let lastSeenAt: String
    let isTrusted: Bool
    let hasSeenTrustPrompt: Bool
    let publicKey: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case deviceType = "device_type"
        case hostname
        case isActive = "is_active"
        case lastSeenAt = "last_seen_at"
        case isTrusted = "is_trusted"
        case hasSeenTrustPrompt = "has_seen_trust_prompt"
        case publicKey = "public_key"
    }
}
