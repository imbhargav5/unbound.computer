//
//  RemoteCommandService.swift
//  unbound-ios
//
//  High-level service for sending remote commands to the macOS daemon
//  via Ably and receiving typed responses.
//

import Foundation
import Logging

private let logger = Logger(label: "app.remote-command")

enum RemoteCommandError: Error, LocalizedError {
    case notAuthenticated
    case noDeviceId
    case sessionNotFound(String)
    case commandRejected(reasonCode: String?, message: String)
    case commandFailed(errorCode: String?, errorMessage: String?)
    case timeout
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .noDeviceId:
            return "Device ID not found in keychain"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .commandRejected(let reasonCode, let message):
            if let reasonCode, !reasonCode.isEmpty {
                return "Command rejected (\(reasonCode)): \(message)"
            }
            return "Command rejected: \(message)"
        case .commandFailed(let errorCode, let errorMessage):
            let code = errorCode ?? "unknown"
            let msg = errorMessage ?? "unknown error"
            return "Command failed (\(code)): \(msg)"
        case .timeout:
            return "Timed out waiting for command response"
        case .transport(let error):
            return "Transport error: \(error.localizedDescription)"
        }
    }
}

struct CreateSessionResult {
    let id: String
    let repositoryId: String
    let title: String
    let status: String
    let isWorktree: Bool
    let worktreePath: String?
    let createdAt: String
}

struct SendMessageResult {
    let status: String
    let sessionId: String
}

struct StopClaudeResult {
    let sessionId: String
    let stopped: Bool
    let message: String?
}

final class RemoteCommandService {
    static let shared = RemoteCommandService()

    private let transport: RemoteCommandTransport
    private let authService: AuthService
    private let keychainService: KeychainService
    private let ackTimeout: TimeInterval
    private let responseTimeout: TimeInterval

    init(
        transport: RemoteCommandTransport = AblyRemoteCommandTransport(),
        authService: AuthService = .shared,
        keychainService: KeychainService = .shared,
        ackTimeout: TimeInterval = 10,
        responseTimeout: TimeInterval = 30
    ) {
        self.transport = transport
        self.authService = authService
        self.keychainService = keychainService
        self.ackTimeout = ackTimeout
        self.responseTimeout = responseTimeout
    }

    // MARK: - Commands

    func createSession(
        targetDeviceId: String,
        repositoryId: String,
        title: String? = nil,
        isWorktree: Bool = false,
        branchName: String? = nil
    ) async throws -> CreateSessionResult {
        var params: [String: AnyCodableValue] = [
            "repository_id": .string(repositoryId),
        ]
        if let title { params["title"] = .string(title) }
        if isWorktree { params["is_worktree"] = .bool(true) }
        if let branchName { params["branch_name"] = .string(branchName) }

        let response = try await sendCommand(
            type: "session.create.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue else {
            throw RemoteCommandError.commandFailed(errorCode: "invalid_result", errorMessage: "Missing result in response")
        }

        return CreateSessionResult(
            id: result["id"]?.stringValue ?? "",
            repositoryId: result["repository_id"]?.stringValue ?? "",
            title: result["title"]?.stringValue ?? "",
            status: result["status"]?.stringValue ?? "",
            isWorktree: result["is_worktree"] == .bool(true),
            worktreePath: result["worktree_path"]?.stringValue,
            createdAt: result["created_at"]?.stringValue ?? ""
        )
    }

    func sendMessage(
        targetDeviceId: String,
        sessionId: String,
        content: String
    ) async throws -> SendMessageResult {
        let params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
            "content": .string(content),
        ]

        let response = try await sendCommand(
            type: "claude.send.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        let result = response.result?.objectValue
        return SendMessageResult(
            status: result?["status"]?.stringValue ?? "started",
            sessionId: result?["session_id"]?.stringValue ?? sessionId
        )
    }

    func stopClaude(
        targetDeviceId: String,
        sessionId: String
    ) async throws -> StopClaudeResult {
        let params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
        ]

        let response = try await sendCommand(
            type: "claude.stop.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        let result = response.result?.objectValue
        return StopClaudeResult(
            sessionId: result?["session_id"]?.stringValue ?? sessionId,
            stopped: result?["stopped"] == .bool(true),
            message: result?["message"]?.stringValue
        )
    }

    // MARK: - Core Send Flow

    private func sendCommand(
        type: String,
        targetDeviceId: String,
        params: [String: AnyCodableValue]
    ) async throws -> RemoteCommandResponse {
        let context = try resolveAuthContext()
        let requestId = UUID().uuidString.lowercased()
        let channel = "remote:\(targetDeviceId):commands"

        let envelope = RemoteCommandEnvelope(
            schemaVersion: 1,
            type: type,
            requestId: requestId,
            requesterDeviceId: context.deviceId,
            targetDeviceId: targetDeviceId,
            requestedAtMs: Self.nowMs(),
            params: params
        )

        logger.info(
            "Sending remote command type=\(type), request_id=\(requestId), target=\(targetDeviceId)"
        )

        // Subscribe for ACK and response before publishing
        async let ackTask: RemoteCommandAckEnvelope = transport.waitForAck(
            channel: channel,
            requestId: requestId,
            timeout: ackTimeout
        )

        async let responseTask: RemoteCommandResponse = transport.waitForCommandResponse(
            channel: channel,
            requestId: requestId,
            timeout: responseTimeout
        )

        // Publish the command
        do {
            try await transport.publishGenericCommand(channel: channel, envelope: envelope)
        } catch {
            throw mapTransportError(error)
        }

        // Wait for ACK (daemon received the command)
        let ack: RemoteCommandAckEnvelope
        do {
            ack = try await ackTask
        } catch {
            throw mapTransportError(error)
        }

        // Verify ACK accepted
        try verifyAck(ack, requestId: requestId)

        // Wait for the actual response
        let response: RemoteCommandResponse
        do {
            response = try await responseTask
        } catch {
            throw mapTransportError(error)
        }

        // Check response status
        guard response.isOk else {
            throw RemoteCommandError.commandFailed(
                errorCode: response.errorCode,
                errorMessage: response.errorMessage
            )
        }

        logger.info(
            "Remote command completed type=\(type), request_id=\(requestId), status=\(response.status)"
        )

        return response
    }

    // MARK: - Helpers

    private struct AuthContext {
        let userId: String
        let deviceId: String
    }

    private func resolveAuthContext() throws -> AuthContext {
        guard let userId = authService.currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
            throw RemoteCommandError.notAuthenticated
        }

        guard let deviceUUID = try? keychainService.getDeviceId(forUser: userId) else {
            throw RemoteCommandError.noDeviceId
        }

        return AuthContext(
            userId: userId,
            deviceId: deviceUUID.uuidString.lowercased()
        )
    }

    private func verifyAck(_ ack: RemoteCommandAckEnvelope, requestId: String) throws {
        guard let resultB64 = ack.resultB64,
              let resultData = Data(base64Encoded: resultB64),
              let decision = try? JSONDecoder().decode(RemoteCommandDecisionResult.self, from: resultData) else {
            logger.warning("ACK missing decodable decision for request_id=\(requestId)")
            // Non-fatal: some ACK formats may not include decision details
            return
        }

        guard decision.status == "accepted" else {
            throw RemoteCommandError.commandRejected(
                reasonCode: decision.reasonCode,
                message: decision.message
            )
        }
    }

    private func mapTransportError(_ error: Error) -> RemoteCommandError {
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
}
