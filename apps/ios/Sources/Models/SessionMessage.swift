import Foundation

/// Encrypted session message from Supabase
/// Matches the new agent_coding_session_messages table schema
struct SessionMessage: Identifiable, Codable, Sendable {
    let id: Int64
    let sessionId: UUID
    let role: MessageRole
    let sequenceNumber: Int64
    let contentEncrypted: Data?  // Base64 decoded
    let contentNonce: Data?      // Base64 decoded
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case role
        case sequenceNumber = "sequence_number"
        case contentEncrypted = "content_encrypted"
        case contentNonce = "content_nonce"
        case createdAt = "created_at"
    }

    /// Decode from Supabase response (handles base64 encoded binary data)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int64.self, forKey: .id)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        sequenceNumber = try container.decode(Int64.self, forKey: .sequenceNumber)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        // Decode role
        let roleString = try container.decode(String.self, forKey: .role)
        role = MessageRole(rawValue: roleString) ?? .system

        // Decode base64-encoded binary data
        if let encryptedString = try container.decodeIfPresent(String.self, forKey: .contentEncrypted) {
            contentEncrypted = Data(base64Encoded: encryptedString)
        } else {
            contentEncrypted = nil
        }

        if let nonceString = try container.decodeIfPresent(String.self, forKey: .contentNonce) {
            contentNonce = Data(base64Encoded: nonceString)
        } else {
            contentNonce = nil
        }
    }
}

/// Message role for display and routing
enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

/// Decrypted message content
/// Contains the eventType and data extracted from the encrypted payload
struct DecryptedMessageContent: Sendable {
    let eventType: String
    let data: [String: Any]

    /// Check if this is a conversation event (streaming content, file changes)
    var isConversationEvent: Bool {
        let conversationTypes: Set<String> = [
            "OUTPUT_CHUNK",
            "STREAMING_THINKING",
            "STREAMING_GENERATING",
            "STREAMING_WAITING",
            "STREAMING_IDLE",
            "TOOL_STARTED",
            "TOOL_OUTPUT_CHUNK",
            "TOOL_COMPLETED",
            "TOOL_FAILED",
            "FILE_CREATED",
            "FILE_MODIFIED",
            "FILE_DELETED",
            "FILE_RENAMED",
            "TODO_LIST_UPDATED",
            "TODO_ITEM_UPDATED",
        ]
        return conversationTypes.contains(eventType)
    }

    /// Check if this is a communication event (commands, state updates)
    var isCommunicationEvent: Bool {
        let communicationTypes: Set<String> = [
            "SESSION_PAUSE_COMMAND",
            "SESSION_RESUME_COMMAND",
            "SESSION_STOP_COMMAND",
            "SESSION_CANCEL_COMMAND",
            "USER_PROMPT_COMMAND",
            "USER_CONFIRMATION_COMMAND",
            "MCQ_RESPONSE_COMMAND",
            "TOOL_APPROVAL_COMMAND",
            "WORKTREE_CREATE_COMMAND",
            "CONFLICTS_FIX_COMMAND",
            "QUESTION_ASKED",
            "QUESTION_ANSWERED",
            "TOOL_APPROVAL_REQUIRED",
            "EXECUTION_STARTED",
            "EXECUTION_COMPLETED",
            "SESSION_STATE_CHANGED",
            "SESSION_ERROR",
            "SESSION_WARNING",
            "RATE_LIMIT_WARNING",
        ]
        return communicationTypes.contains(eventType)
    }
}
