//
//  DatabaseModels.swift
//  unbound-ios
//
//  GRDB Record types for database persistence.
//  These map between SQLite tables and Swift app models.
//

import Foundation
import GRDB

// MARK: - Repository Record

struct RepositoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "repositories"

    var id: String
    var path: String
    var name: String
    var lastAccessedAt: Date
    var addedAt: Date
    var isGitRepository: Bool
    var sessionsPath: String?
    var defaultBranch: String?
    var defaultRemote: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, path, name
        case lastAccessedAt = "last_accessed_at"
        case addedAt = "added_at"
        case isGitRepository = "is_git_repository"
        case sessionsPath = "sessions_path"
        case defaultBranch = "default_branch"
        case defaultRemote = "default_remote"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Session Record

struct SessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_coding_sessions"

    var id: String
    var repositoryId: String
    var title: String
    var claudeSessionId: String?
    var isWorktree: Bool
    var worktreePath: String?
    var status: String
    var createdAt: Date
    var lastAccessedAt: Date
    var updatedAt: Date

    /// Backward-compatible alias used by older UI mapping code.
    var name: String { title }

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case repositoryId = "repository_id"
        case claudeSessionId = "claude_session_id"
        case isWorktree = "is_worktree"
        case worktreePath = "worktree_path"
        case createdAt = "created_at"
        case lastAccessedAt = "last_accessed_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - ChatTab Record

struct ChatTabRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_coding_session_chat_tabs"

    var id: String
    var sessionId: String
    var title: String
    var claudeSessionId: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case sessionId = "session_id"
        case claudeSessionId = "claude_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Message Record

struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_coding_session_messages"

    var id: String
    var sessionId: String
    var content: String
    var timestamp: Date
    var isStreaming: Bool
    var sequenceNumber: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content, timestamp
        case sessionId = "session_id"
        case isStreaming = "is_streaming"
        case sequenceNumber = "sequence_number"
        case createdAt = "created_at"
    }
}

// MARK: - ImageUpload Record

struct ImageUploadRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_coding_session_image_uploads"

    var id: String
    var messageId: String?
    var sessionId: String
    var filename: String
    var storedFilename: String
    var mimeType: String
    var fileSize: Int
    var width: Int?
    var height: Int?
    var checksum: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, filename, width, height, checksum
        case messageId = "message_id"
        case sessionId = "session_id"
        case storedFilename = "stored_filename"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case createdAt = "created_at"
    }
}

// MARK: - Attachment Record

struct AttachmentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_coding_session_attachments"

    var id: String
    var messageId: String?
    var sessionId: String
    var filename: String
    var storedFilename: String
    var fileType: String
    var mimeType: String
    var fileSize: Int
    var checksum: String?
    var metadataJson: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, filename, checksum
        case messageId = "message_id"
        case sessionId = "session_id"
        case storedFilename = "stored_filename"
        case fileType = "file_type"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case metadataJson = "metadata_json"
        case createdAt = "created_at"
    }
}

// MARK: - UserSetting Record

struct UserSettingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "user_settings"

    var key: String
    var value: String
    var valueType: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case key, value
        case valueType = "value_type"
        case updatedAt = "updated_at"
    }
}

// MARK: - Attachment File Type

enum AttachmentFileType: String, Codable {
    case image
    case text
    case pdf
    case other

    var subdirectory: String {
        switch self {
        case .image: return "images"
        case .text, .pdf: return "text"
        case .other: return "other"
        }
    }

    static func from(mimeType: String) -> AttachmentFileType {
        if mimeType.hasPrefix("image/") {
            return .image
        } else if mimeType.hasPrefix("text/") || mimeType == "application/json" {
            return .text
        } else if mimeType == "application/pdf" {
            return .pdf
        } else {
            return .other
        }
    }

    static func from(filename: String) -> AttachmentFileType {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff":
            return .image
        case "txt", "md", "json", "xml", "csv", "log", "yaml", "yml":
            return .text
        case "pdf":
            return .pdf
        default:
            return .other
        }
    }
}

// MARK: - Coding Session Status (for database)

enum CodingSessionStatus: String, Codable {
    case active
    case paused
    case ended
}
