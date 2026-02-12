//
//  AblyConversationService.swift
//  unbound-ios
//
//  Ably realtime subscription service for session conversation messages.
//

import Foundation
import Logging

#if canImport(Ably)
import Ably
#endif

private let ablyConversationLogger = Logger(label: "app.ably.conversation")

enum AblyConversationServiceError: Error, LocalizedError {
    case notConfigured
    case authFailed(String)
    case invalidMessageData
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Ably conversation subscription is not configured"
        case .authFailed(let message):
            return "Ably conversation auth failed: \(message)"
        case .invalidMessageData:
            return "Ably conversation payload was invalid"
        case .unsupportedPlatform:
            return "Ably conversation subscription is unavailable in this build"
        }
    }
}

protocol SessionDetailConversationStreaming {
    func subscribe(sessionId: UUID) -> AsyncThrowingStream<AblyConversationMessageEnvelope, Error>
}

final class AblyConversationService: SessionDetailConversationStreaming {
    #if canImport(Ably)
    private let realtime: ARTRealtime?
    #endif

    init(
        tokenAuthURL: URL = Config.ablyTokenAuthURL,
        authService: AuthService = .shared,
        keychainService: KeychainService = .shared
    ) {
        #if canImport(Ably)
        let resolvedTokenAuthURL = tokenAuthURL
        let resolvedAuthService = authService
        let resolvedKeychainService = keychainService
        let options = ARTClientOptions()
        options.autoConnect = true
        options.authCallback = { _, callback in
            Self.fetchTokenDetails(
                tokenAuthURL: resolvedTokenAuthURL,
                authService: resolvedAuthService,
                keychainService: resolvedKeychainService,
                callback: callback
            )
        }
        self.realtime = ARTRealtime(options: options)
        ablyConversationLogger.info("Ably conversation service initialized with token auth")
        #endif
    }

    deinit {
        #if canImport(Ably)
        realtime?.close()
        #endif
    }

    func subscribe(sessionId: UUID) -> AsyncThrowingStream<AblyConversationMessageEnvelope, Error> {
        #if canImport(Ably)
        AsyncThrowingStream { continuation in
            guard let realtime else {
                continuation.finish(throwing: AblyConversationServiceError.notConfigured)
                return
            }

            let expectedSessionID = sessionId.uuidString.lowercased()
            let channelName = Config.conversationChannel(sessionId: sessionId)
            let channelRef = realtime.channels.get(channelName)
            ablyConversationLogger.debug(
                "Subscribing to Ably conversation channel=\(channelName), event=\(Config.conversationMessageEventName)"
            )

            let listener = channelRef.subscribe(Config.conversationMessageEventName) { message in
                do {
                    guard let envelope: AblyConversationMessageEnvelope = try Self.decodeMessageData(message.data) else {
                        return
                    }
                    guard envelope.sessionId.lowercased() == expectedSessionID else {
                        ablyConversationLogger.debug(
                            "Ignoring conversation payload for mismatched session expected=\(expectedSessionID), actual=\(envelope.sessionId.lowercased())"
                        )
                        return
                    }
                    continuation.yield(envelope)
                } catch {
                    ablyConversationLogger.error(
                        "Failed decoding Ably conversation payload on channel=\(channelName): \(error.localizedDescription)"
                    )
                }
            }

            continuation.onTermination = { _ in
                channelRef.unsubscribe(listener)
            }
        }
        #else
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AblyConversationServiceError.unsupportedPlatform)
        }
        #endif
    }

    #if canImport(Ably)
    private struct TokenRequestBody: Encodable {
        let deviceId: String

        enum CodingKeys: String, CodingKey {
            case deviceId = "deviceId"
        }
    }

    private struct TokenDetailsPayload: Decodable {
        let token: String
        let expires: Int64?
        let issued: Int64?
        let capability: String?
        let clientId: String?

        enum CodingKeys: String, CodingKey {
            case token
            case expires
            case issued
            case capability
            case clientId = "clientId"
        }
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let details: String?
    }

    private static func fetchTokenDetails(
        tokenAuthURL: URL,
        authService: AuthService,
        keychainService: KeychainService,
        callback: @escaping ARTTokenDetailsCompatibleCallback
    ) {
        Task {
            do {
                let tokenDetails = try await requestTokenDetails(
                    tokenAuthURL: tokenAuthURL,
                    authService: authService,
                    keychainService: keychainService
                )
                callback(tokenDetails, nil)
            } catch {
                let mappedError = mapTokenAuthError(error)
                ablyConversationLogger.error(
                    "Failed to fetch Ably conversation token details: \(mappedError.localizedDescription)"
                )
                callback(nil, mappedError.asNSError())
            }
        }
    }

    private static func requestTokenDetails(
        tokenAuthURL: URL,
        authService: AuthService,
        keychainService: KeychainService
    ) async throws -> ARTTokenDetails {
        let resolvedUserId = authService.currentUserId ?? (try? keychainService.getSupabaseUserId())
        guard let userId = resolvedUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
            throw AblyConversationServiceError.authFailed("User is not authenticated")
        }

        let deviceId: UUID
        do {
            deviceId = try keychainService.getDeviceId(forUser: userId)
        } catch {
            throw AblyConversationServiceError.authFailed("Device ID is not available in keychain")
        }

        let accessToken: String
        do {
            accessToken = try await authService.getAccessToken()
        } catch {
            throw AblyConversationServiceError.authFailed("Unable to obtain access token")
        }

        var request = URLRequest(url: tokenAuthURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            TokenRequestBody(deviceId: deviceId.uuidString.lowercased())
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AblyConversationServiceError.authFailed("Token auth server returned invalid response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverMessage = decodeServerErrorMessage(from: data)
            throw AblyConversationServiceError.authFailed(
                "Token endpoint returned HTTP \(httpResponse.statusCode): \(serverMessage)"
            )
        }

        let payload: TokenDetailsPayload
        do {
            payload = try JSONDecoder().decode(TokenDetailsPayload.self, from: data)
        } catch {
            throw AblyConversationServiceError.authFailed("Token endpoint returned invalid payload")
        }

        guard !payload.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AblyConversationServiceError.authFailed("Token endpoint returned empty token")
        }

        let expiresDate = payload.expires.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        let issuedDate = payload.issued.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        return ARTTokenDetails(
            token: payload.token,
            expires: expiresDate,
            issued: issuedDate,
            capability: payload.capability,
            clientId: payload.clientId
        )
    }

    private static func decodeServerErrorMessage(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            if let error = payload.error, !error.isEmpty {
                return error
            }
            if let details = payload.details, !details.isEmpty {
                return details
            }
        }

        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return raw
        }

        return "Unknown error"
    }

    private static func mapTokenAuthError(_ error: Error) -> AblyConversationServiceError {
        if let mapped = error as? AblyConversationServiceError {
            return mapped
        }
        return .authFailed(error.localizedDescription)
    }

    private static func decodeMessageData<T: Decodable>(_ data: Any?) throws -> T? {
        guard let data else { return nil }

        if let typed = data as? T {
            return typed
        }
        if let rawData = data as? Data {
            return try JSONDecoder().decode(T.self, from: rawData)
        }
        if let rawString = data as? String {
            guard let rawData = rawString.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(T.self, from: rawData)
        }
        if JSONSerialization.isValidJSONObject(data) {
            let rawData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(T.self, from: rawData)
        }

        throw AblyConversationServiceError.invalidMessageData
    }
    #endif
}

private extension AblyConversationServiceError {
    func asNSError() -> NSError {
        NSError(
            domain: "com.unbound.ios.ably.conversation",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: localizedDescription]
        )
    }
}
