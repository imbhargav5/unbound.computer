//
//  SessionRuntimeStatusService.swift
//  unbound-macos
//
//  Tracks Supabase Realtime runtime status updates for agent coding sessions.
//

import Foundation
import Logging
import Realtime
import Supabase

private let runtimeStatusLogger = Logger(label: "app.runtime-status")

@Observable
@MainActor
final class SessionRuntimeStatusService {
    static let shared = SessionRuntimeStatusService()

    private(set) var runtimeStatusBySessionId: [UUID: RuntimeStatusEnvelope] = [:]

    private var supabaseClient: SupabaseClient?
    private var realtimeChannel: RealtimeChannelV2?
    private var activeUserId: String?
    private var lastUpdatedAtBySessionId: [UUID: Int64] = [:]

    private init() {}

    func start(userId: String, daemonClient: DaemonClient = .shared) async {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if activeUserId == normalizedUserId, realtimeChannel != nil {
            runtimeStatusLogger.debug("SessionRuntimeStatusService start ignored (already running)")
            return
        }

        stop()
        activeUserId = normalizedUserId

        do {
            let session = try await daemonClient.getSupabaseAuthSession()
            let client = SupabaseClient(
                supabaseURL: Config.supabaseURL,
                supabaseKey: Config.supabasePublishableKey
            )
            supabaseClient = client
            await client.realtimeV2.setAuth(session.accessToken)
            await subscribeToSessionUpdates(client: client, userId: normalizedUserId)
            runtimeStatusLogger.info("SessionRuntimeStatusService started for user: \(normalizedUserId)")
        } catch {
            runtimeStatusLogger.error("Failed to start SessionRuntimeStatusService: \(error)")
            stop()
        }
    }

    func stop() {
        unsubscribeFromSessions()
        supabaseClient = nil
        activeUserId = nil
        runtimeStatusBySessionId = [:]
        lastUpdatedAtBySessionId = [:]
        runtimeStatusLogger.info("SessionRuntimeStatusService stopped")
    }

    private func subscribeToSessionUpdates(client: SupabaseClient, userId: String) async {
        unsubscribeFromSessions()

        let channel = client.realtimeV2.channel("session-runtime-status-\(userId)")
        let changes = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "agent_coding_sessions",
            filter: "user_id=eq.\(userId)"
        )

        await channel.subscribe()
        realtimeChannel = channel

        runtimeStatusLogger.info("Subscribed to runtime status changes")

        Task { [weak self] in
            for await change in changes {
                guard let self else { break }
                await self.handleRuntimeStatusChange(change)
            }
        }
    }

    private func handleRuntimeStatusChange(_ change: UpdateAction) {
        guard let record = change.record as? [String: Any] else { return }

        let sessionIdString = (record["id"] as? String) ?? (record["session_id"] as? String)
        guard let sessionIdString, let sessionId = UUID(uuidString: sessionIdString) else { return }

        if let envelope = decodeEnvelope(from: record) {
            applyEnvelope(envelope, sessionId: sessionId)
            return
        }

        guard record["runtime_status"] == nil else { return }
        guard let updatedAtMs = parseUpdatedAtMs(from: record["runtime_status_updated_at"]) else { return }

        let deviceId = (record["device_id"] as? String) ?? "unknown"
        let envelope = RuntimeStatusEnvelope(
            schemaVersion: 1,
            codingSession: CodingSessionRuntimeState(status: .idle, errorMessage: nil),
            deviceId: deviceId,
            sessionId: sessionIdString.lowercased(),
            updatedAtMs: updatedAtMs
        )
        applyEnvelope(envelope, sessionId: sessionId)
    }

    private func decodeEnvelope(from record: [String: Any]) -> RuntimeStatusEnvelope? {
        guard let raw = record["runtime_status"] else { return nil }

        do {
            if let decoded = try RuntimeStatusEnvelope.decodeEnvelopePayload(raw) {
                return decoded
            }
        } catch {
            runtimeStatusLogger.warning("Failed to decode runtime status payload: \(error)")
        }

        return nil
    }

    private func applyEnvelope(_ envelope: RuntimeStatusEnvelope, sessionId: UUID) {
        let updatedAtMs = envelope.updatedAtMs
        if let previousUpdatedAt = lastUpdatedAtBySessionId[sessionId], previousUpdatedAt >= updatedAtMs {
            return
        }

        runtimeStatusBySessionId[sessionId] = envelope
        lastUpdatedAtBySessionId[sessionId] = updatedAtMs
    }

    private func parseUpdatedAtMs(from raw: Any?) -> Int64? {
        guard let raw else { return nil }

        if let intValue = raw as? Int64 { return intValue }
        if let intValue = raw as? Int { return Int64(intValue) }
        if let doubleValue = raw as? Double { return Int64(doubleValue) }
        if let stringValue = raw as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: stringValue) ?? ISO8601DateFormatter().date(from: stringValue) {
                return Int64(date.timeIntervalSince1970 * 1000.0)
            }
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
