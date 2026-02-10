//
//  SessionDetailMessageRemoteSource.swift
//  unbound-ios
//
//  Supabase source for encrypted session messages.
//

import Foundation
import Logging
import Supabase

private let sessionDetailRemoteLogger = Logger(label: "app.session-detail.remote-source")

protocol SessionDetailMessageRemoteSource {
    func fetchEncryptedRows(sessionId: UUID) async throws -> [EncryptedSessionMessageRow]
}

protocol SessionDetailSupabaseQuerying {
    func fetchEncryptedSessionMessages(
        sessionId: UUID,
        tableName: String,
        selectClause: String
    ) async throws -> Data
}

final class AuthServiceSessionDetailSupabaseClient: SessionDetailSupabaseQuerying {
    private let authService: AuthService

    init(authService: AuthService = .shared) {
        self.authService = authService
    }

    func fetchEncryptedSessionMessages(
        sessionId: UUID,
        tableName: String,
        selectClause: String
    ) async throws -> Data {
        let response = try await authService.supabaseClient
            .from(tableName)
            .select(selectClause)
            .eq("session_id", value: sessionId.uuidString)
            .order("sequence_number", ascending: true)
            .execute()

        return response.data
    }
}

final class SupabaseSessionDetailMessageRemoteSource: SessionDetailMessageRemoteSource {
    static let tableName = "agent_coding_session_messages"
    static let selectClause = "id,sequence_number,created_at,content_encrypted,content_nonce"

    private let supabaseClient: SessionDetailSupabaseQuerying

    init(supabaseClient: SessionDetailSupabaseQuerying = AuthServiceSessionDetailSupabaseClient()) {
        self.supabaseClient = supabaseClient
    }

    func fetchEncryptedRows(sessionId: UUID) async throws -> [EncryptedSessionMessageRow] {
        do {
            let payload = try await supabaseClient.fetchEncryptedSessionMessages(
                sessionId: sessionId,
                tableName: Self.tableName,
                selectClause: Self.selectClause
            )
            return try EncryptedSessionMessageDecoder.parseRows(from: payload)
        } catch let error as SessionDetailMessageError {
            throw error
        } catch {
            sessionDetailRemoteLogger.error(
                "Failed to fetch encrypted rows for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
            )
            throw SessionDetailMessageError.fetchFailed
        }
    }
}
