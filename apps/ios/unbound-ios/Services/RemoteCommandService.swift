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
    case targetUnavailable(String)
    case sessionNotFound(String)
    case commandRejected(reasonCode: String?, message: String)
    case commandFailed(
        errorCode: String?,
        errorMessage: String?,
        errorData: AnyCodableValue?
    )
    case timeout
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .noDeviceId:
            return "Device ID not found in keychain"
        case .targetUnavailable(let targetDeviceId):
            return "Target device daemon is offline: \(targetDeviceId)"
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .commandRejected(let reasonCode, let message):
            if let reasonCode, !reasonCode.isEmpty {
                return "Command rejected (\(reasonCode)): \(message)"
            }
            return "Command rejected: \(message)"
        case .commandFailed(let errorCode, let errorMessage, let errorData):
            let code = errorCode ?? "unknown"
            let msg = errorMessage ?? "unknown error"
            if let details = Self.formatErrorDetails(errorData), !details.isEmpty {
                return "Command failed (\(code)): \(msg) [\(details)]"
            }
            return "Command failed (\(code)): \(msg)"
        case .timeout:
            return "Timed out waiting for command response"
        case .transport(let error):
            return "Transport error: \(error.localizedDescription)"
        }
    }

    private static func formatErrorDetails(_ errorData: AnyCodableValue?) -> String? {
        guard let errorData else {
            return nil
        }

        guard let data = errorData.objectValue else {
            if let rendered = renderErrorDataValue(errorData), !rendered.isEmpty {
                return "error_data=\(rendered)"
            }
            return nil
        }

        var parts: [String] = []
        if let stage = data["stage"]?.stringValue, !stage.isEmpty {
            parts.append("stage=\(stage)")
        }
        if let stderr = data["stderr"]?.stringValue, !stderr.isEmpty {
            parts.append("stderr=\(stderr)")
        }
        if let cleanupError = data["cleanup_error"]?.stringValue, !cleanupError.isEmpty {
            parts.append("cleanup_error=\(cleanupError)")
        }
        if parts.isEmpty, let rendered = renderErrorDataValue(errorData), !rendered.isEmpty {
            parts.append("error_data=\(rendered)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func renderErrorDataValue(_ value: AnyCodableValue) -> String? {
        switch value {
        case .string(let text):
            return text
        case .int(let number):
            return String(number)
        case .double(let number):
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return nil
        case .object(let object):
            let pairs = object
                .keys
                .sorted()
                .compactMap { key -> String? in
                    guard let rendered = renderErrorDataValue(object[key] ?? .null),
                          !rendered.isEmpty else {
                        return nil
                    }
                    return "\(key)=\(rendered)"
                }
            return pairs.isEmpty ? "{}" : "{\(pairs.joined(separator: ", "))}"
        case .array(let values):
            let rendered = values.compactMap { renderErrorDataValue($0) }
            return "[\(rendered.joined(separator: ", "))]"
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

struct RemotePullRequest {
    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool
    let mergeStateStatus: String?
    let reviewDecision: String?
}

struct CreatePRResult {
    let url: String
    let pullRequest: RemotePullRequest
}

struct ListPRsResult {
    let pullRequests: [RemotePullRequest]
    let count: Int
}

struct PRChecksSummary {
    let total: Int
    let passing: Int
    let failing: Int
    let pending: Int
    let skipped: Int
    let cancelled: Int
}

struct PRCheckItem {
    let name: String
    let state: String?
    let bucket: String?
    let workflow: String?
}

struct PRChecksResult {
    let checks: [PRCheckItem]
    let summary: PRChecksSummary
}

struct MergePRResult {
    let merged: Bool
    let mergeMethod: String
    let deletedBranch: Bool
    let pullRequest: RemotePullRequest
}

struct GitCommitResult {
    let oid: String
    let shortOid: String
    let summary: String
}

struct GitPushResult {
    let remote: String
    let branch: String
    let success: Bool
}

final class RemoteCommandService {
    static let shared = RemoteCommandService()

    private let transport: RemoteCommandTransport
    private let authService: AuthService
    private let keychainService: KeychainService
    private let authContextResolver: (() throws -> (userId: String, deviceId: String))?
    private let targetAvailabilityResolver: ((String) -> DeviceDaemonAvailability)?
    private let ackTimeout: TimeInterval
    private let responseTimeout: TimeInterval

    init(
        transport: RemoteCommandTransport = AblyRemoteCommandTransport(),
        authService: AuthService = .shared,
        keychainService: KeychainService = .shared,
        authContextResolver: (() throws -> (userId: String, deviceId: String))? = nil,
        targetAvailabilityResolver: ((String) -> DeviceDaemonAvailability)? = nil,
        ackTimeout: TimeInterval = 10,
        responseTimeout: TimeInterval = 30
    ) {
        self.transport = transport
        self.authService = authService
        self.keychainService = keychainService
        self.authContextResolver = authContextResolver
        self.targetAvailabilityResolver = targetAvailabilityResolver
        self.ackTimeout = ackTimeout
        self.responseTimeout = responseTimeout
    }

    // MARK: - Commands

    func createSession(
        targetDeviceId: String,
        repositoryId: String,
        title: String? = nil,
        isWorktree: Bool = false,
        baseBranch: String? = nil,
        worktreeBranch: String? = nil,
        worktreeName: String? = nil,
        branchName: String? = nil
    ) async throws -> CreateSessionResult {
        var params: [String: AnyCodableValue] = [
            "repository_id": .string(repositoryId),
            "is_worktree": .bool(isWorktree),
        ]
        if let title { params["title"] = .string(title) }
        if let baseBranch, !baseBranch.isEmpty {
            params["base_branch"] = .string(baseBranch)
        }
        if let worktreeBranch, !worktreeBranch.isEmpty {
            params["worktree_branch"] = .string(worktreeBranch)
        } else if let branchName, !branchName.isEmpty {
            params["branch_name"] = .string(branchName)
        }
        if let worktreeName, !worktreeName.isEmpty {
            params["worktree_name"] = .string(worktreeName)
        }

        let response = try await sendCommand(
            type: "session.create.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue else {
            throw RemoteCommandError.commandFailed(
                errorCode: "invalid_result",
                errorMessage: "Missing result in response",
                errorData: nil
            )
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
        content: String,
        permissionMode: String? = nil
    ) async throws -> SendMessageResult {
        var params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
            "content": .string(content),
        ]
        if let permissionMode {
            params["permission_mode"] = .string(permissionMode)
        }

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

    func createPR(
        targetDeviceId: String,
        sessionId: String,
        title: String,
        body: String? = nil,
        base: String? = nil,
        head: String? = nil,
        draft: Bool = false,
        reviewers: [String] = [],
        labels: [String] = [],
        maintainerCanModify: Bool? = nil
    ) async throws -> CreatePRResult {
        var params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
            "title": .string(title),
        ]
        if let body { params["body"] = .string(body) }
        if let base { params["base"] = .string(base) }
        if let head { params["head"] = .string(head) }
        if draft { params["draft"] = .bool(true) }
        if !reviewers.isEmpty {
            params["reviewers"] = .array(reviewers.map(AnyCodableValue.string))
        }
        if !labels.isEmpty {
            params["labels"] = .array(labels.map(AnyCodableValue.string))
        }
        if let maintainerCanModify {
            params["maintainer_can_modify"] = .bool(maintainerCanModify)
        }

        let response = try await sendCommand(
            type: "gh.pr.create.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue,
              let url = result["url"]?.stringValue,
              let pullRequestPayload = result["pull_request"]?.objectValue else {
            throw RemoteCommandError.commandFailed(
                errorCode: "invalid_result",
                errorMessage: "Missing create PR result fields",
                errorData: nil
            )
        }

        return CreatePRResult(
            url: url,
            pullRequest: parsePullRequest(from: pullRequestPayload)
        )
    }

    func viewPR(
        targetDeviceId: String,
        sessionId: String,
        selector: String? = nil
    ) async throws -> RemotePullRequest {
        var params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
        ]
        if let selector, !selector.isEmpty {
            params["selector"] = .string(selector)
        }

        let response = try await sendCommand(
            type: "gh.pr.view.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue,
              let pullRequestPayload = result["pull_request"]?.objectValue else {
            throw RemoteCommandError.commandFailed(
                errorCode: "invalid_result",
                errorMessage: "Missing pull request detail",
                errorData: nil
            )
        }

        return parsePullRequest(from: pullRequestPayload)
    }

    func listPRs(
        targetDeviceId: String,
        sessionId: String,
        state: String = "open",
        limit: Int = 20,
        base: String? = nil,
        head: String? = nil
    ) async throws -> ListPRsResult {
        var params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
            "state": .string(state),
            "limit": .int(limit),
        ]
        if let base, !base.isEmpty {
            params["base"] = .string(base)
        }
        if let head, !head.isEmpty {
            params["head"] = .string(head)
        }

        let response = try await sendCommand(
            type: "gh.pr.list.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue else {
            throw RemoteCommandError.commandFailed(
                errorCode: "invalid_result",
                errorMessage: "Missing list PRs result",
                errorData: nil
            )
        }

        let pullRequests = result["pull_requests"]?.arrayValue?.compactMap { item -> RemotePullRequest? in
            guard let payload = item.objectValue else { return nil }
            return parsePullRequest(from: payload)
        } ?? []

        return ListPRsResult(
            pullRequests: pullRequests,
            count: result["count"]?.intValue ?? pullRequests.count
        )
    }

    func prChecks(
        targetDeviceId: String,
        sessionId: String,
        selector: String? = nil
    ) async throws -> PRChecksResult {
        var params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
        ]
        if let selector, !selector.isEmpty {
            params["selector"] = .string(selector)
        }

        let response = try await sendCommand(
            type: "gh.pr.checks.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue else {
            throw RemoteCommandError.commandFailed(
                errorCode: "invalid_result",
                errorMessage: "Missing PR checks result",
                errorData: nil
            )
        }

        let checks = result["checks"]?.arrayValue?.compactMap { item -> PRCheckItem? in
            guard let payload = item.objectValue else { return nil }
            return PRCheckItem(
                name: payload["name"]?.stringValue ?? "unknown",
                state: payload["state"]?.stringValue,
                bucket: payload["bucket"]?.stringValue,
                workflow: payload["workflow"]?.stringValue
            )
        } ?? []

        let summaryPayload = result["summary"]?.objectValue ?? [:]
        let summary = PRChecksSummary(
            total: summaryPayload["total"]?.intValue ?? checks.count,
            passing: summaryPayload["passing"]?.intValue ?? 0,
            failing: summaryPayload["failing"]?.intValue ?? 0,
            pending: summaryPayload["pending"]?.intValue ?? 0,
            skipped: summaryPayload["skipped"]?.intValue ?? 0,
            cancelled: summaryPayload["cancelled"]?.intValue ?? 0
        )

        return PRChecksResult(checks: checks, summary: summary)
    }

    func mergePR(
        targetDeviceId: String,
        sessionId: String,
        selector: String? = nil,
        mergeMethod: String = "squash",
        deleteBranch: Bool = false,
        subject: String? = nil,
        body: String? = nil
    ) async throws -> MergePRResult {
        var params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
            "merge_method": .string(mergeMethod),
            "delete_branch": .bool(deleteBranch),
        ]
        if let selector, !selector.isEmpty {
            params["selector"] = .string(selector)
        }
        if let subject, !subject.isEmpty {
            params["subject"] = .string(subject)
        }
        if let body {
            params["body"] = .string(body)
        }

        let response = try await sendCommand(
            type: "gh.pr.merge.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue,
              let pullRequestPayload = result["pull_request"]?.objectValue else {
            throw RemoteCommandError.commandFailed(
                errorCode: "invalid_result",
                errorMessage: "Missing merge PR result",
                errorData: nil
            )
        }

        return MergePRResult(
            merged: result["merged"]?.boolValue ?? true,
            mergeMethod: result["merge_method"]?.stringValue ?? mergeMethod,
            deletedBranch: result["deleted_branch"]?.boolValue ?? deleteBranch,
            pullRequest: parsePullRequest(from: pullRequestPayload)
        )
    }

    func commitChanges(
        targetDeviceId: String,
        sessionId: String,
        message: String,
        authorName: String? = nil,
        authorEmail: String? = nil,
        stageAll: Bool = false
    ) async throws -> GitCommitResult {
        var params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
            "message": .string(message),
        ]
        if let authorName, !authorName.isEmpty {
            params["author_name"] = .string(authorName)
        }
        if let authorEmail, !authorEmail.isEmpty {
            params["author_email"] = .string(authorEmail)
        }
        if stageAll {
            params["stage_all"] = .bool(true)
        }

        let response = try await sendCommand(
            type: "git.commit.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue else {
            throw RemoteCommandError.commandFailed(
                errorCode: "invalid_result",
                errorMessage: "Missing git commit result",
                errorData: nil
            )
        }

        return GitCommitResult(
            oid: result["oid"]?.stringValue ?? "",
            shortOid: result["short_oid"]?.stringValue ?? "",
            summary: result["summary"]?.stringValue ?? ""
        )
    }

    func pushChanges(
        targetDeviceId: String,
        sessionId: String,
        remote: String? = nil,
        branch: String? = nil
    ) async throws -> GitPushResult {
        var params: [String: AnyCodableValue] = [
            "session_id": .string(sessionId),
        ]
        if let remote, !remote.isEmpty {
            params["remote"] = .string(remote)
        }
        if let branch, !branch.isEmpty {
            params["branch"] = .string(branch)
        }

        let response = try await sendCommand(
            type: "git.push.v1",
            targetDeviceId: targetDeviceId,
            params: params
        )

        guard let result = response.result?.objectValue else {
            throw RemoteCommandError.commandFailed(
                errorCode: "invalid_result",
                errorMessage: "Missing git push result",
                errorData: nil
            )
        }

        return GitPushResult(
            remote: result["remote"]?.stringValue ?? "",
            branch: result["branch"]?.stringValue ?? "",
            success: result["success"]?.boolValue ?? false
        )
    }

    // MARK: - Core Send Flow

    private func sendCommand(
        type: String,
        targetDeviceId: String,
        params: [String: AnyCodableValue]
    ) async throws -> RemoteCommandResponse {
        let normalizedTargetDeviceId = targetDeviceId.lowercased()
        let availability: DeviceDaemonAvailability
        if let targetAvailabilityResolver {
            availability = targetAvailabilityResolver(normalizedTargetDeviceId)
        } else {
            availability = await MainActor.run {
                DevicePresenceService.shared.daemonAvailability(id: normalizedTargetDeviceId)
            }
        }
        if availability == .offline {
            throw RemoteCommandError.targetUnavailable(normalizedTargetDeviceId)
        }

        let context = try resolveAuthContext()
        let requestId = UUID().uuidString.lowercased()
        let channel = "remote:\(normalizedTargetDeviceId):commands"

        let envelope = RemoteCommandEnvelope(
            schemaVersion: 1,
            type: type,
            requestId: requestId,
            requesterDeviceId: context.deviceId,
            targetDeviceId: normalizedTargetDeviceId,
            requestedAtMs: Self.nowMs(),
            params: params
        )

        logger.info(
            "Sending remote command type=\(type), request_id=\(requestId), target=\(normalizedTargetDeviceId)"
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
                errorMessage: response.errorMessage,
                errorData: response.errorData
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
        if let authContextResolver {
            let context = try authContextResolver()
            return AuthContext(userId: context.userId, deviceId: context.deviceId)
        }

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

    private func parsePullRequest(from payload: [String: AnyCodableValue]) -> RemotePullRequest {
        RemotePullRequest(
            number: payload["number"]?.intValue ?? 0,
            title: payload["title"]?.stringValue ?? "",
            url: payload["url"]?.stringValue ?? "",
            state: payload["state"]?.stringValue ?? "UNKNOWN",
            isDraft: payload["is_draft"]?.boolValue ?? false,
            mergeStateStatus: payload["merge_state_status"]?.stringValue,
            reviewDecision: payload["review_decision"]?.stringValue
        )
    }

    private static func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
