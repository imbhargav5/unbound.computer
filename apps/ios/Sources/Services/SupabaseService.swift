import Foundation
import Supabase

enum OrderBy {
    case ascending
    case descending
}

@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    private let client: SupabaseClient

    init() {
        self.client = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Sessions

    func fetchSessions() async throws -> [CodingSession] {
        Config.log("📥 Fetching sessions from Supabase")

        let response: [CodingSession] = try await client
            .from("agent_coding_sessions")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        Config.log("✅ Fetched \(response.count) sessions")
        return response
    }

    func fetchSession(_ sessionId: UUID) async throws -> CodingSession {
        Config.log("📥 Fetching session \(sessionId) from Supabase")

        let response: CodingSession = try await client
            .from("agent_coding_sessions")
            .select()
            .eq("id", value: sessionId.uuidString)
            .single()
            .execute()
            .value

        Config.log("✅ Fetched session: \(response.title ?? "Untitled")")
        return response
    }

    // MARK: - Session Messages (Encrypted)

    /// Fetch encrypted session messages from Supabase
    /// Messages must be decrypted using the session key
    func fetchSessionMessages(
        sessionId: UUID,
        limit: Int = 100,
        offset: Int = 0,
        orderBy: OrderBy = .ascending
    ) async throws -> [SessionMessage] {
        Config.log("📥 Fetching encrypted messages for session \(sessionId) (limit: \(limit), offset: \(offset))")

        let response: [SessionMessage] = try await client
            .from("agent_coding_session_messages")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .order("sequence_number", ascending: orderBy == .ascending)
            .limit(limit)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value

        Config.log("✅ Fetched \(response.count) encrypted messages")
        return response
    }

    /// Fetch encrypted session messages with pagination
    func fetchSessionMessagesPaginated(
        sessionId: UUID,
        afterSequenceNumber: Int64?,
        limit: Int = 50
    ) async throws -> [SessionMessage] {
        Config.log("📥 Fetching paginated messages (after sequence: \(afterSequenceNumber ?? -1))")

        var query = client
            .from("agent_coding_session_messages")
            .select()
            .eq("session_id", value: sessionId.uuidString)

        if let afterSequenceNumber {
            query = query.gt("sequence_number", value: Int(afterSequenceNumber))
        }

        let response: [SessionMessage] = try await query
            .order("sequence_number", ascending: true)
            .limit(limit)
            .execute()
            .value

        Config.log("✅ Fetched \(response.count) paginated messages")
        return response
    }

    /// Get count of encrypted messages for a session
    func fetchSessionMessagesCount(sessionId: UUID) async throws -> Int {
        Config.log("📥 Fetching message count for session \(sessionId)")

        let response = try await client
            .from("agent_coding_session_messages")
            .select("count", head: true)
            .eq("session_id", value: sessionId.uuidString)
            .execute()

        let count = response.count ?? 0
        Config.log("✅ Message count: \(count)")
        return count
    }

    // MARK: - Legacy Messages (Deprecated - Use fetchSessionMessages)

    @available(*, deprecated, message: "Use fetchSessionMessages instead")
    func fetchMessages(
        sessionId: UUID,
        limit: Int = 100,
        offset: Int = 0,
        orderBy: OrderBy = .ascending
    ) async throws -> [ConversationEvent] {
        Config.log("⚠️ Using deprecated fetchMessages - migrate to fetchSessionMessages")

        let response: [ConversationEvent] = try await client
            .from("agent_coding_session_messages")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .order("created_at", ascending: orderBy == .ascending)
            .limit(limit)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value

        return response
    }

    @available(*, deprecated, message: "Use fetchSessionMessagesPaginated instead")
    func fetchMessagesPaginated(
        sessionId: UUID,
        afterMessageId: String?,
        limit: Int = 50
    ) async throws -> [ConversationEvent] {
        var query = client
            .from("agent_coding_session_messages")
            .select()
            .eq("session_id", value: sessionId.uuidString)

        if let afterMessageId {
            query = query.gt("created_at", value: afterMessageId)
        }

        let response: [ConversationEvent] = try await query
            .order("created_at", ascending: true)
            .limit(limit)
            .execute()
            .value

        return response
    }

    @available(*, deprecated, message: "Use fetchSessionMessagesCount instead")
    func fetchMessagesCount(sessionId: UUID) async throws -> Int {
        try await fetchSessionMessagesCount(sessionId: sessionId)
    }

    // MARK: - Legacy Event Methods (deprecated, use message methods)

    @available(*, deprecated, renamed: "fetchMessages")
    func fetchEvents(
        sessionId: UUID,
        limit: Int = 100,
        offset: Int = 0,
        orderBy: OrderBy = .ascending
    ) async throws -> [ConversationEvent] {
        try await fetchMessages(sessionId: sessionId, limit: limit, offset: offset, orderBy: orderBy)
    }

    @available(*, deprecated, renamed: "fetchMessagesPaginated")
    func fetchEventsPaginated(
        sessionId: UUID,
        afterEventId: String?,
        limit: Int = 50
    ) async throws -> [ConversationEvent] {
        try await fetchMessagesPaginated(sessionId: sessionId, afterMessageId: afterEventId, limit: limit)
    }

    @available(*, deprecated, renamed: "fetchMessagesCount")
    func fetchEventsCount(sessionId: UUID) async throws -> Int {
        try await fetchMessagesCount(sessionId: sessionId)
    }
}
