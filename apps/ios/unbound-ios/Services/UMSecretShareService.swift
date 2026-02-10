//
//  UMSecretShareService.swift
//  unbound-ios
//
//  Resolves coding session secrets with local keychain-first behavior and
//  remote command fetch via Ably on cache miss.
//

import Foundation
import Logging
import Supabase

private let umSecretLogger = Logger(label: "app.um-secret")

protocol SessionSecretEnvelopeDecrypting {
    func decryptCodingSessionSecretEnvelope(
        encapsulationPublicKey: String,
        nonceB64: String,
        ciphertextB64: String,
        sessionId: UUID,
        userId: String
    ) throws -> String
}

extension SessionSecretService: SessionSecretEnvelopeDecrypting {}

enum UMSecretShareError: Error, LocalizedError {
    case notAuthenticated
    case noDeviceId
    case sessionNotFound(UUID)
    case remoteRejected(reasonCode: String?, message: String)
    case remoteExecutionFailed(errorCode: String?)
    case invalidAckPayload
    case invalidResponsePayload
    case timeout
    case transport(Error)
    case decryptionFailed(Error)
    case invalidSecretFormat
    case storageFailed(Error)
    case secretNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .noDeviceId:
            return "Device ID not found in keychain"
        case .sessionNotFound(let sessionId):
            return "Coding session not found: \(sessionId)"
        case .remoteRejected(let reasonCode, let message):
            if let reasonCode, !reasonCode.isEmpty {
                return "Remote command rejected (\(reasonCode)): \(message)"
            }
            return "Remote command rejected: \(message)"
        case .remoteExecutionFailed(let errorCode):
            if let errorCode, !errorCode.isEmpty {
                return "Remote secret sharing failed: \(errorCode)"
            }
            return "Remote secret sharing failed"
        case .invalidAckPayload:
            return "Invalid ACK payload from remote command channel"
        case .invalidResponsePayload:
            return "Invalid response payload from session secret channel"
        case .timeout:
            return "Timed out waiting for remote secret response"
        case .transport(let error):
            return "Remote transport error: \(error.localizedDescription)"
        case .decryptionFailed(let error):
            return "Failed to decrypt session secret: \(error.localizedDescription)"
        case .invalidSecretFormat:
            return "Session secret format is invalid"
        case .storageFailed(let error):
            return "Failed to store session secret locally: \(error.localizedDescription)"
        case .secretNotFound(let sessionId):
            return "No encrypted secret found for this device in session: \(sessionId)"
        }
    }
}

final class UMSecretShareService {
    static let shared = UMSecretShareService()

    private let transport: RemoteCommandTransport
    private let sessionSecretService: SessionSecretEnvelopeDecrypting
    private let sessionSecretKeyStore: SessionSecretKeyStoring
    private let authService: AuthService
    private let keychainService: KeychainService
    private let timeoutSeconds: TimeInterval

    init(
        transport: RemoteCommandTransport = AblyRemoteCommandTransport(),
        sessionSecretService: SessionSecretEnvelopeDecrypting = SessionSecretService.shared,
        sessionSecretKeyStore: SessionSecretKeyStoring = SessionSecretKeyStore.shared,
        authService: AuthService = .shared,
        keychainService: KeychainService = .shared,
        timeoutSeconds: TimeInterval = 10
    ) {
        self.transport = transport
        self.sessionSecretService = sessionSecretService
        self.sessionSecretKeyStore = sessionSecretKeyStore
        self.authService = authService
        self.keychainService = keychainService
        self.timeoutSeconds = timeoutSeconds
    }

    func fetchSessionSecret(sessionId: UUID) async throws -> String {
        let context = try await resolveContext(sessionId: sessionId)
        return try await fetchSessionSecret(sessionId: sessionId, context: context)
    }

    func fetchSessionSecret(sessionId: UUID, context: RequestContext) async throws -> String {
        if let cached = try loadCachedSecret(sessionId: sessionId, userId: context.userId) {
            return cached
        }

        let secret = try await fetchViaRemote(sessionId: sessionId, context: context)
        do {
            try sessionSecretKeyStore.set(secret: secret, sessionId: sessionId, userId: context.userId)
        } catch {
            throw UMSecretShareError.storageFailed(error)
        }
        return secret
    }

    // MARK: - Remote Flow

    private func fetchViaRemote(sessionId: UUID, context: RequestContext) async throws -> String {
        let requestId = UUID().uuidString.lowercased()
        let remoteChannel = Self.remoteCommandsChannel(for: context.targetDeviceId)
        let secretsChannel = Self.sessionSecretsChannel(
            senderDeviceId: context.targetDeviceId,
            receiverDeviceId: context.requesterDeviceId
        )

        let payload = UMSecretRequestCommandPayload(
            type: "um.secret.request.v1",
            requestId: requestId,
            sessionId: sessionId.uuidString.lowercased(),
            requesterDeviceId: context.requesterDeviceId,
            targetDeviceId: context.targetDeviceId,
            requestedAtMs: Self.nowMs()
        )
        umSecretLogger.debug(
            "Requesting remote session secret request_id=\(requestId), session_id=\(sessionId.uuidString.lowercased()), requester_device_id=\(context.requesterDeviceId), target_device_id=\(context.targetDeviceId)"
        )

        async let ackTask: RemoteCommandAckEnvelope = transport.waitForAck(
            channel: remoteChannel,
            requestId: requestId,
            timeout: timeoutSeconds
        )

        async let responseTask: SessionSecretResponseEnvelope = transport.waitForSessionSecretResponse(
            channel: secretsChannel,
            requestId: requestId,
            sessionId: sessionId.uuidString.lowercased(),
            timeout: timeoutSeconds
        )

        do {
            try await transport.publishRemoteCommand(channel: remoteChannel, payload: payload)
        } catch {
            throw mapTransportError(error)
        }

        let ack: RemoteCommandAckEnvelope
        do {
            ack = try await ackTask
        } catch {
            throw mapTransportError(error)
        }

        let decision = try decodeDecision(from: ack)
        guard ack.status == "accepted", decision.status == "accepted" else {
            throw UMSecretShareError.remoteRejected(
                reasonCode: decision.reasonCode,
                message: decision.message
            )
        }

        let response: SessionSecretResponseEnvelope
        do {
            response = try await responseTask
        } catch {
            throw mapTransportError(error)
        }

        guard response.status == "ok" else {
            if response.errorCode == "session_secret_not_found" {
                throw UMSecretShareError.secretNotFound(sessionId)
            }
            throw UMSecretShareError.remoteExecutionFailed(errorCode: response.errorCode)
        }

        guard let encapsulationPubkeyB64 = response.encapsulationPubkeyB64,
              let nonceB64 = response.nonceB64,
              let ciphertextB64 = response.ciphertextB64 else {
            throw UMSecretShareError.invalidResponsePayload
        }

        do {
            let secret = try sessionSecretService.decryptCodingSessionSecretEnvelope(
                encapsulationPublicKey: encapsulationPubkeyB64,
                nonceB64: nonceB64,
                ciphertextB64: ciphertextB64,
                sessionId: sessionId,
                userId: context.userId.uuidString
            )
            _ = try SessionSecretFormat.parseKey(secret: secret)
            umSecretLogger.info(
                "Resolved and decrypted remote session secret request_id=\(requestId), session_id=\(sessionId.uuidString.lowercased())"
            )
            return secret
        } catch is SessionSecretFormatError {
            throw UMSecretShareError.invalidSecretFormat
        } catch {
            umSecretLogger.error(
                "Failed to decrypt remote session secret request_id=\(requestId), session_id=\(sessionId.uuidString.lowercased()), user_id=\(context.userId.uuidString): \(error.localizedDescription)"
            )
            throw UMSecretShareError.decryptionFailed(error)
        }
    }

    // MARK: - Context Resolution

    struct RequestContext {
        let userId: UUID
        let requesterDeviceId: String
        let targetDeviceId: String
    }

    private struct SessionDeviceRow: Codable {
        let deviceId: String

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id"
        }
    }

    private func resolveContext(sessionId: UUID) async throws -> RequestContext {
        guard let userIdString = authService.currentUserId,
              let userId = UUID(uuidString: userIdString) else {
            throw UMSecretShareError.notAuthenticated
        }

        guard let requesterDeviceUUID = try? keychainService.getDeviceId(forUser: userIdString) else {
            throw UMSecretShareError.noDeviceId
        }

        let targetDeviceId = try await fetchTargetDeviceId(sessionId: sessionId, userId: userId)

        return RequestContext(
            userId: userId,
            requesterDeviceId: requesterDeviceUUID.uuidString.lowercased(),
            targetDeviceId: targetDeviceId
        )
    }

    // MARK: - Local Cache

    private func loadCachedSecret(sessionId: UUID, userId: UUID) throws -> String? {
        let cached = try sessionSecretKeyStore.get(sessionId: sessionId, userId: userId)
        guard let cached else {
            return nil
        }

        do {
            _ = try SessionSecretFormat.parseKey(secret: cached)
            return cached
        } catch {
            umSecretLogger.warning(
                "Found invalid cached session secret for session \(sessionId.uuidString.lowercased()); deleting cached value"
            )
            try? sessionSecretKeyStore.delete(sessionId: sessionId, userId: userId)
            return nil
        }
    }

    private func fetchTargetDeviceId(sessionId: UUID, userId: UUID) async throws -> String {
        do {
            let response = try await authService.supabaseClient
                .from("agent_coding_sessions")
                .select("device_id")
                .eq("id", value: sessionId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()

            let row = try JSONDecoder().decode(SessionDeviceRow.self, from: response.data)
            let targetDeviceId = row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)

            guard UUID(uuidString: targetDeviceId) != nil else {
                throw UMSecretShareError.sessionNotFound(sessionId)
            }

            return targetDeviceId.lowercased()
        } catch let error as UMSecretShareError {
            throw error
        } catch {
            throw UMSecretShareError.sessionNotFound(sessionId)
        }
    }

    // MARK: - Helpers

    private func decodeDecision(from ack: RemoteCommandAckEnvelope) throws -> RemoteCommandDecisionResult {
        guard let resultB64 = ack.resultB64,
              let resultData = Data(base64Encoded: resultB64) else {
            throw UMSecretShareError.invalidAckPayload
        }

        do {
            return try JSONDecoder().decode(RemoteCommandDecisionResult.self, from: resultData)
        } catch {
            throw UMSecretShareError.invalidAckPayload
        }
    }

    private func mapTransportError(_ error: Error) -> UMSecretShareError {
        if let transportError = error as? RemoteCommandTransportError {
            switch transportError {
            case .timeout:
                return .timeout
            default:
                return .transport(transportError)
            }
        }
        return .transport(error)
    }

    private static func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    private static func remoteCommandsChannel(for targetDeviceId: String) -> String {
        "remote:\(targetDeviceId):commands"
    }

    private static func sessionSecretsChannel(senderDeviceId: String, receiverDeviceId: String) -> String {
        "session:secrets:\(senderDeviceId):\(receiverDeviceId)"
    }
}
