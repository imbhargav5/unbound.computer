//
//  SupabaseModels.swift
//  unbound-macos
//
//  Codable models for Supabase API interactions.
//  Maps local session data to Supabase table schemas.
//

import Foundation

// MARK: - Agent Coding Session (Supabase)

/// Model for upserting session to Supabase `agent_coding_sessions` table
struct SupabaseAgentCodingSession: Codable {
    let id: String
    let userId: String
    let deviceId: String
    let repositoryId: String
    let status: String
    let sessionStartedAt: String
    let lastHeartbeatAt: String
    let isWorktree: Bool
    let worktreePath: String?
    let workingDirectory: String?
    let currentBranch: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceId = "device_id"
        case repositoryId = "repository_id"
        case status
        case sessionStartedAt = "session_started_at"
        case lastHeartbeatAt = "last_heartbeat_at"
        case isWorktree = "is_worktree"
        case worktreePath = "worktree_path"
        case workingDirectory = "working_directory"
        case currentBranch = "current_branch"
    }

    /// Create from local Session model
    static func from(
        session: Session,
        userId: String,
        deviceId: UUID
    ) -> SupabaseAgentCodingSession {
        let now = ISO8601DateFormatter().string(from: Date())
        let startedAt = ISO8601DateFormatter().string(from: session.createdAt)

        return SupabaseAgentCodingSession(
            id: session.id.uuidString,
            userId: userId,
            deviceId: deviceId.uuidString,
            repositoryId: session.repositoryId.uuidString,
            status: mapSessionStatus(session.status),
            sessionStartedAt: startedAt,
            lastHeartbeatAt: now,
            isWorktree: session.isWorktree,
            worktreePath: session.worktreePath,
            workingDirectory: session.worktreePath,
            currentBranch: nil
        )
    }

    /// Map local SessionStatus to Supabase coding_session_status enum
    private static func mapSessionStatus(_ status: SessionStatus) -> String {
        switch status {
        case .active:
            return "active"
        case .archived:
            return "ended"
        case .error:
            return "ended"
        }
    }
}

// MARK: - Session State Update (Supabase)

/// Model for updating session heartbeat and status in Supabase
struct SupabaseSessionHeartbeat: Codable {
    let lastHeartbeatAt: String
    let status: String?

    enum CodingKeys: String, CodingKey {
        case lastHeartbeatAt = "last_heartbeat_at"
        case status
    }
}

// MARK: - Repository (Supabase)

/// Model for upserting repository to Supabase `repositories` table
struct SupabaseRepository: Codable {
    let id: String
    let userId: String
    let deviceId: String
    let name: String
    let localPath: String
    let remoteUrl: String?
    let defaultBranch: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceId = "device_id"
        case name
        case localPath = "local_path"
        case remoteUrl = "remote_url"
        case defaultBranch = "default_branch"
        case status
    }
}

// MARK: - Agent Coding Session Secret (Supabase)

/// Model for upserting session secrets to Supabase `agent_coding_session_secrets` table
/// This stores encrypted session secrets for each device that needs to decrypt session messages
struct SupabaseAgentCodingSessionSecret: Codable {
    let sessionId: String
    let deviceId: String
    let encryptedSecret: Data  // ephemeral_public_key (32 bytes) + encrypted_data

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case deviceId = "device_id"
        case encryptedSecret = "encrypted_secret"
    }
}

// MARK: - Device (Supabase Read)

/// Model for reading device info from Supabase `devices` table
struct SupabaseDevice: Codable {
    let id: String
    let userId: String
    let name: String
    let deviceType: String
    let publicKey: String?
    let isTrusted: Bool
    let capabilities: DeviceCapabilities?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case deviceType = "device_type"
        case publicKey = "public_key"
        case isTrusted = "is_trusted"
        case capabilities
    }
}

// MARK: - Device Capabilities

struct DeviceCapabilities: Codable {
    let cli: CliCapabilities?
    let metadata: CapabilitiesMetadata?

    struct CliCapabilities: Codable {
        let claude: ToolCapabilities?
        let gh: ToolCapabilities?
        let codex: ToolCapabilities?
        let ollama: ToolCapabilities?
    }

    struct ToolCapabilities: Codable {
        let installed: Bool
        let path: String?
        let models: [String]?
    }

    struct CapabilitiesMetadata: Codable {
        let schemaVersion: Int?
        let collectedAt: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case collectedAt = "collected_at"
        }
    }
}
