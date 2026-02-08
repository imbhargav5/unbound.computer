//
//  DaemonClient+API.swift
//  unbound-macos
//
//  Typed API methods for the daemon client.
//  Provides high-level methods that wrap the raw call() method.
//

import Foundation
import AppKit
import Logging

private let logger = Logger(label: "app.daemon.api")

// MARK: - Health

extension DaemonClient {
    /// Check daemon health.
    func health() async throws -> Bool {
        let response = try await call(method: .health)
        return response.isSuccess
    }
}

// MARK: - Authentication

extension DaemonClient {
    /// Get current authentication status.
    func getAuthStatus() async throws -> DaemonAuthStatus {
        let response = try await call(method: .authStatus)
        return try response.resultAs(DaemonAuthStatus.self)
    }

    /// Start login flow with email and password.
    /// - Parameters:
    ///   - email: User's email address.
    ///   - password: User's password.
    func loginWithPassword(email: String, password: String) async throws {
        let params: [String: Any] = [
            "email": email,
            "password": password
        ]
        _ = try await call(method: .authLogin, params: params)
    }

    /// Start login flow with OAuth provider.
    /// - Parameters:
    ///   - provider: OAuth provider ("github", "google", "gitlab").
    ///   - email: Unused for social login (kept for compatibility).
    func loginWithProvider(_ provider: String, email: String? = nil) async throws {
        var params: [String: Any] = ["provider": provider]
        if let email {
            params["email"] = email
        }

        let startResponse = try await call(method: .authLogin, params: params)
        let socialStart = try startResponse.resultAs(DaemonSocialLoginStart.self)

        guard let loginUrl = URL(string: socialStart.loginUrl) else {
            throw DaemonError.decodingFailed("Invalid social login URL")
        }

        guard NSWorkspace.shared.open(loginUrl) else {
            throw DaemonError.connectionFailed("Failed to open browser for social login")
        }

        _ = try await call(method: .authCompleteSocial, params: [
            "login_id": socialStart.loginId,
            "timeout_secs": 180
        ])
    }

    /// Logout and clear session.
    func logout() async throws {
        _ = try await call(method: .authLogout)
    }
}

private struct DaemonSocialLoginStart: Codable {
    let status: String
    let provider: String
    let loginId: String
    let loginUrl: String

    enum CodingKeys: String, CodingKey {
        case status
        case provider
        case loginId = "login_id"
        case loginUrl = "login_url"
    }
}

// MARK: - Sessions

extension DaemonClient {
    /// List all sessions, optionally filtered by repository.
    func listSessions(repositoryId: String? = nil) async throws -> [DaemonSession] {
        var params: [String: Any]? = nil
        if let repositoryId {
            params = ["repository_id": repositoryId]
        }
        let response = try await call(method: .sessionList, params: params)

        guard let result = response.resultAsDict(),
              let sessionsData = result["sessions"] as? [[String: Any]] else {
            logger.debug("No sessions in response or invalid format")
            return []
        }

        logger.debug("Parsing \(sessionsData.count) sessions from daemon")

        let decoder = JSONDecoder()

        return sessionsData.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
                logger.warning("Failed to serialize session dict: \(dict)")
                return nil
            }
            do {
                return try decoder.decode(DaemonSession.self, from: data)
            } catch {
                logger.warning("Failed to decode session: \(error), dict: \(dict)")
                return nil
            }
        }
    }

    /// Create a new session.
    func createSession(
        repositoryId: String,
        title: String? = nil,
        isWorktree: Bool = false
    ) async throws -> DaemonSession {
        var params: [String: Any] = ["repository_id": repositoryId]
        if let title {
            params["title"] = title
        }
        if isWorktree {
            params["is_worktree"] = true
        }
        let response = try await call(method: .sessionCreate, params: params)

        // Daemon returns session data directly (not wrapped in "session" key)
        guard let sessionData = response.resultAsDict() else {
            throw DaemonError.noResult
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try JSONSerialization.data(withJSONObject: sessionData)
        return try decoder.decode(DaemonSession.self, from: data)
    }

    /// Get a session by ID.
    func getSession(sessionId: String) async throws -> DaemonSession {
        let response = try await call(method: .sessionGet, params: ["session_id": sessionId])

        guard let result = response.resultAsDict(),
              let sessionData = result["session"] as? [String: Any] else {
            throw DaemonError.notFound("session")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try JSONSerialization.data(withJSONObject: sessionData)
        return try decoder.decode(DaemonSession.self, from: data)
    }

    /// Delete a session.
    func deleteSession(sessionId: String) async throws {
        _ = try await call(method: .sessionDelete, params: ["session_id": sessionId])
    }
}

// MARK: - Messages

extension DaemonClient {
    /// List messages for a session.
    func listMessages(sessionId: String, limit: Int? = nil, offset: Int? = nil) async throws -> [DaemonMessage] {
        var params: [String: Any] = ["session_id": sessionId]
        if let limit {
            params["limit"] = limit
        }
        if let offset {
            params["offset"] = offset
        }

        let response = try await call(method: .messageList, params: params)

        guard let result = response.resultAsDict(),
              let messagesData = result["messages"] as? [[String: Any]] else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return messagesData.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(DaemonMessage.self, from: data)
        }
    }

    /// Send a message (adds to session without triggering Claude).
    func sendMessage(sessionId: String, role: String, content: String) async throws -> DaemonMessage {
        let response = try await call(method: .messageSend, params: [
            "session_id": sessionId,
            "role": role,
            "content": content
        ])

        guard let result = response.resultAsDict(),
              let messageData = result["message"] as? [String: Any] else {
            throw DaemonError.noResult
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try JSONSerialization.data(withJSONObject: messageData)
        return try decoder.decode(DaemonMessage.self, from: data)
    }
}

// MARK: - Claude

extension DaemonClient {
    /// Send a message to Claude (persists user message, spawns Claude CLI).
    func sendToClaude(
        sessionId: String,
        content: String,
        workingDirectory: String? = nil,
        modelIdentifier: String? = nil
    ) async throws {
        var params: [String: Any] = [
            "session_id": sessionId,
            "content": content
        ]
        if let workingDirectory {
            params["working_directory"] = workingDirectory
        }
        if let modelIdentifier {
            params["model"] = modelIdentifier
        }

        _ = try await call(method: .claudeSend, params: params)
        logger.info("Sent message to Claude for session \(sessionId)")
    }

    /// Get Claude process status.
    func getClaudeStatus(sessionId: String? = nil) async throws -> DaemonClaudeStatus {
        var params: [String: Any]? = nil
        if let sessionId {
            params = ["session_id": sessionId]
        }
        let response = try await call(method: .claudeStatus, params: params)
        return try response.resultAs(DaemonClaudeStatus.self)
    }

    /// Stop Claude process.
    func stopClaude(sessionId: String) async throws {
        _ = try await call(method: .claudeStop, params: ["session_id": sessionId])
        logger.info("Stopped Claude for session \(sessionId)")
    }
}

// MARK: - Repositories

extension DaemonClient {
    /// List all repositories.
    func listRepositories() async throws -> [DaemonRepository] {
        let response = try await call(method: .repositoryList)

        guard let result = response.resultAsDict(),
              let reposData = result["repositories"] as? [[String: Any]] else {
            logger.debug("No repositories in response or invalid format")
            return []
        }

        logger.debug("Parsing \(reposData.count) repositories from daemon")

        let decoder = JSONDecoder()

        return reposData.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
                logger.warning("Failed to serialize repository dict: \(dict)")
                return nil
            }
            do {
                return try decoder.decode(DaemonRepository.self, from: data)
            } catch {
                logger.warning("Failed to decode repository: \(error), dict: \(dict)")
                return nil
            }
        }
    }

    /// Add a repository.
    func addRepository(name: String, path: String) async throws -> DaemonRepository {
        let response = try await call(method: .repositoryAdd, params: [
            "name": name,
            "path": path
        ])

        guard let result = response.resultAsDict(),
              let repoData = result["repository"] as? [String: Any] else {
            throw DaemonError.noResult
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try JSONSerialization.data(withJSONObject: repoData)
        return try decoder.decode(DaemonRepository.self, from: data)
    }

    /// Remove a repository.
    func removeRepository(repositoryId: String) async throws {
        _ = try await call(method: .repositoryRemove, params: ["repository_id": repositoryId])
    }

    /// List files for a session root or subdirectory (relative path).
    func listRepositoryFiles(
        sessionId: String,
        relativePath: String = "",
        includeHidden: Bool = false
    ) async throws -> [DaemonFileEntry] {
        var params: [String: Any] = ["session_id": sessionId]
        if !relativePath.isEmpty {
            params["relative_path"] = relativePath
        }
        if includeHidden {
            params["include_hidden"] = true
        }

        let response = try await call(method: .repositoryListFiles, params: params)

        guard let result = response.resultAsDict(),
              let entriesData = result["entries"] as? [[String: Any]] else {
            logger.debug("No file entries in response or invalid format")
            return []
        }

        let decoder = JSONDecoder()

        return entriesData.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
                logger.warning("Failed to serialize file entry dict: \(dict)")
                return nil
            }
            do {
                return try decoder.decode(DaemonFileEntry.self, from: data)
            } catch {
                logger.warning("Failed to decode file entry: \(error), dict: \(dict)")
                return nil
            }
        }
    }

    /// Read file contents for a session-relative path.
    func readRepositoryFile(
        sessionId: String,
        relativePath: String,
        maxBytes: Int? = nil
    ) async throws -> DaemonFileContent {
        var params: [String: Any] = [
            "session_id": sessionId,
            "relative_path": relativePath
        ]
        if let maxBytes {
            params["max_bytes"] = maxBytes
        }

        let response = try await call(method: .repositoryReadFile, params: params)
        return try response.resultAs(DaemonFileContent.self)
    }

    /// Read a slice of file contents for a session-relative path.
    func readRepositoryFileSlice(
        sessionId: String,
        relativePath: String,
        startLine: Int,
        endLineExclusive: Int,
        maxBytes: Int? = nil
    ) async throws -> DaemonFileSlice {
        var params: [String: Any] = [
            "session_id": sessionId,
            "relative_path": relativePath,
            "start_line": startLine,
            "end_line_exclusive": endLineExclusive
        ]
        if let maxBytes {
            params["max_bytes"] = maxBytes
        }

        let response = try await call(method: .repositoryReadFileSlice, params: params)
        return try response.resultAs(DaemonFileSlice.self)
    }

    /// Write full file contents for a session-relative path.
    func writeRepositoryFile(
        sessionId: String,
        relativePath: String,
        content: String,
        expectedRevision: DaemonFileRevision?,
        force: Bool = false
    ) async throws -> DaemonWriteResult {
        var params: [String: Any] = [
            "session_id": sessionId,
            "relative_path": relativePath,
            "content": content
        ]
        if let expectedRevision {
            params["expected_revision"] = [
                "token": expectedRevision.token,
                "len_bytes": expectedRevision.lenBytes,
                "modified_unix_ns": expectedRevision.modifiedUnixNs
            ]
        }
        if force {
            params["force"] = true
        }

        let response = try await call(method: .repositoryWriteFile, params: params)
        return try response.resultAs(DaemonWriteResult.self)
    }

    /// Replace a line range in a file for a session-relative path.
    func replaceRepositoryFileRange(
        sessionId: String,
        relativePath: String,
        startLine: Int,
        endLineExclusive: Int,
        replacement: String,
        expectedRevision: DaemonFileRevision?,
        force: Bool = false
    ) async throws -> DaemonWriteResult {
        var params: [String: Any] = [
            "session_id": sessionId,
            "relative_path": relativePath,
            "start_line": startLine,
            "end_line_exclusive": endLineExclusive,
            "replacement": replacement
        ]
        if let expectedRevision {
            params["expected_revision"] = [
                "token": expectedRevision.token,
                "len_bytes": expectedRevision.lenBytes,
                "modified_unix_ns": expectedRevision.modifiedUnixNs
            ]
        }
        if force {
            params["force"] = true
        }

        let response = try await call(method: .repositoryReplaceFileRange, params: params)
        return try response.resultAs(DaemonWriteResult.self)
    }
}

// MARK: - Git

extension DaemonClient {
    /// Get git status for a path (returns new GitStatusResult).
    func getGitStatusV2(path: String) async throws -> GitStatusResult {
        let response = try await call(method: .gitStatus, params: ["path": path])
        return try response.resultAs(GitStatusResult.self)
    }

    /// Get git status for a path (legacy format).
    func getGitStatus(path: String) async throws -> DaemonGitStatus {
        let response = try await call(method: .gitStatus, params: ["path": path])
        return try response.resultAs(DaemonGitStatus.self)
    }

    /// Get diff for a specific file.
    func getGitDiff(path: String, filePath: String) async throws -> String {
        let response = try await call(method: .gitDiffFile, params: [
            "path": path,
            "file_path": filePath
        ])

        guard let result = response.resultAsDict(),
              let diff = result["diff"] as? String else {
            return ""
        }

        return diff
    }

    /// Get commit history for a repository.
    /// - Parameters:
    ///   - path: Repository path
    ///   - limit: Maximum number of commits (default 50)
    ///   - offset: Number of commits to skip (for pagination)
    ///   - branch: Optional branch name (default: HEAD)
    func getGitLog(
        path: String,
        limit: Int? = nil,
        offset: Int? = nil,
        branch: String? = nil
    ) async throws -> GitLogResult {
        var params: [String: Any] = ["path": path]
        if let limit { params["limit"] = limit }
        if let offset { params["offset"] = offset }
        if let branch { params["branch"] = branch }

        let response = try await call(method: .gitLog, params: params)
        return try response.resultAs(GitLogResult.self)
    }

    /// Get all branches for a repository.
    func getGitBranches(path: String) async throws -> GitBranchesResult {
        let response = try await call(method: .gitBranches, params: ["path": path])
        return try response.resultAs(GitBranchesResult.self)
    }

    /// Stage files for commit.
    func stageFiles(path: String, files: [String]) async throws {
        _ = try await call(method: .gitStage, params: [
            "path": path,
            "paths": files
        ])
    }

    /// Unstage files (remove from index).
    func unstageFiles(path: String, files: [String]) async throws {
        _ = try await call(method: .gitUnstage, params: [
            "path": path,
            "paths": files
        ])
    }

    /// Discard working tree changes.
    func discardChanges(path: String, files: [String]) async throws {
        _ = try await call(method: .gitDiscard, params: [
            "path": path,
            "paths": files
        ])
    }

    /// Create a commit from staged changes.
    func gitCommit(
        path: String,
        message: String,
        authorName: String? = nil,
        authorEmail: String? = nil
    ) async throws -> GitCommitResultResponse {
        var params: [String: Any] = ["path": path, "message": message]
        if let authorName { params["author_name"] = authorName }
        if let authorEmail { params["author_email"] = authorEmail }
        let response = try await call(method: .gitCommit, params: params)
        return try response.resultAs(GitCommitResultResponse.self)
    }

    /// Push commits to remote.
    func gitPush(
        path: String,
        remote: String? = nil,
        branch: String? = nil
    ) async throws -> GitPushResultResponse {
        var params: [String: Any] = ["path": path]
        if let remote { params["remote"] = remote }
        if let branch { params["branch"] = branch }
        let response = try await call(method: .gitPush, params: params)
        return try response.resultAs(GitPushResultResponse.self)
    }
}

// MARK: - Terminal

extension DaemonClient {
    /// Run a terminal command.
    func runTerminalCommand(
        sessionId: String,
        command: String,
        workingDirectory: String? = nil
    ) async throws -> String {
        var params: [String: Any] = [
            "session_id": sessionId,
            "command": command
        ]
        if let workingDirectory {
            params["working_directory"] = workingDirectory
        }

        let response = try await call(method: .terminalRun, params: params)

        guard let result = response.resultAsDict(),
              let commandId = result["command_id"] as? String else {
            throw DaemonError.noResult
        }

        return commandId
    }

    /// Get terminal command status.
    func getTerminalStatus(commandId: String) async throws -> (isRunning: Bool, exitCode: Int?) {
        let response = try await call(method: .terminalStatus, params: ["command_id": commandId])

        guard let result = response.resultAsDict() else {
            throw DaemonError.noResult
        }

        let isRunning = result["is_running"] as? Bool ?? false
        let exitCode = result["exit_code"] as? Int

        return (isRunning, exitCode)
    }

    /// Stop a terminal command.
    func stopTerminalCommand(commandId: String) async throws {
        _ = try await call(method: .terminalStop, params: ["command_id": commandId])
    }
}

// MARK: - Convenience

extension DaemonClient {
    /// Ensure connection is established.
    func ensureConnected() async throws {
        if !connectionState.isConnected {
            try await connect()
        }
    }

    /// Get sessions as local Session models.
    func getSessions(repositoryId: UUID? = nil) async throws -> [Session] {
        let repoIdStr = repositoryId?.uuidString.lowercased()
        let daemonSessions = try await listSessions(repositoryId: repoIdStr)
        return daemonSessions.compactMap { $0.toSession() }
    }

    /// Get repositories as local Repository models.
    func getRepositories() async throws -> [Repository] {
        let daemonRepos = try await listRepositories()
        return daemonRepos.compactMap { $0.toRepository() }
    }
}
