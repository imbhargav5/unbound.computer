//
//  SessionTitleSyncService.swift
//  unbound-ios
//
//  Applies Supabase realtime session title updates into SQLite.
//

import Foundation
import Logging
import Realtime
import Supabase

private let sessionTitleLogger = Logger(label: "app.session-title-sync")

@Observable
@MainActor
final class SessionTitleSyncService {
    static let shared = SessionTitleSyncService()

    private var supabase: SupabaseClient?
    private var userId: String?
    private var realtimeChannel: RealtimeChannelV2?
    private var lastUpdatedAtBySessionId: [UUID: Date] = [:]

    private let sessionsRepository: SessionRepository
    private let syncedDataService: SyncedDataService

    private init(
        databaseService: DatabaseService = .shared,
        syncedDataService: SyncedDataService = .shared
    ) {
        self.sessionsRepository = SessionRepository(databaseService: databaseService)
        self.syncedDataService = syncedDataService
    }

    func start(supabase: SupabaseClient, userId: String) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCurrentUserId = self.userId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedCurrentUserId == normalizedUserId, realtimeChannel != nil {
            sessionTitleLogger.debug("SessionTitleSyncService start ignored (already running)")
            return
        }

        if self.supabase != nil || self.userId != nil {
            stop()
        }

        self.supabase = supabase
        self.userId = normalizedUserId

        Task {
            await subscribeToSessionUpdates()
        }

        sessionTitleLogger.info("SessionTitleSyncService started for user: \(normalizedUserId)")
    }

    func stop() {
        unsubscribeFromSessions()
        supabase = nil
        userId = nil
        lastUpdatedAtBySessionId = [:]
        sessionTitleLogger.info("SessionTitleSyncService stopped")
    }

    private func subscribeToSessionUpdates() async {
        guard let supabase, let userId else { return }

        unsubscribeFromSessions()

        let channel = supabase.realtimeV2.channel("session-title-updates-\(userId)")
        let changes = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "agent_coding_sessions",
            filter: "user_id=eq.\(userId)"
        )

        await channel.subscribe()
        realtimeChannel = channel

        sessionTitleLogger.info("Subscribed to session title changes")

        Task { [weak self] in
            for await change in changes {
                guard let self else { break }
                await handleTitleChange(change)
            }
        }
    }

    private func handleTitleChange(_ change: UpdateAction) async {
        guard let record = change.record as? [String: Any] else { return }

        let sessionIdString = (record["id"] as? String) ?? (record["session_id"] as? String)
        guard let sessionIdString, let sessionId = UUID(uuidString: sessionIdString) else { return }

        let title = record["title"] as? String
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let updatedAt = parseUpdatedAt(from: record["updated_at"]) ?? Date()

        if let previousUpdatedAt = lastUpdatedAtBySessionId[sessionId], previousUpdatedAt >= updatedAt {
            return
        }

        do {
            try await sessionsRepository.updateTitle(
                id: sessionId,
                title: title,
                updatedAt: updatedAt
            )
            lastUpdatedAtBySessionId[sessionId] = updatedAt
            await syncedDataService.refresh()
        } catch {
            sessionTitleLogger.warning("Failed to update session title: \(error)")
        }
    }

    private func parseUpdatedAt(from raw: Any?) -> Date? {
        guard let raw else { return nil }

        if let date = raw as? Date { return date }
        if let stringValue = raw as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: stringValue) {
                return date
            }
            return ISO8601DateFormatter().date(from: stringValue)
        }

        return nil
    }

    private func unsubscribeFromSessions() {
        if let channel = realtimeChannel {
            Task {
                await channel.unsubscribe()
            }
            realtimeChannel = nil
        }
    }
}
