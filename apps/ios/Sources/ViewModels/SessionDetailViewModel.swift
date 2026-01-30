import Foundation
import SwiftUI

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(Error)
}

/// ViewModel for displaying session details and real-time events
/// Migrated to @Observable for iOS 17+ (from ObservableObject + @Published)
@MainActor
@Observable
final class SessionDetailViewModel {
    var session: CodingSession?
    var events: [ConversationEvent] = []
    var isLoadingCold = false
    var connectionState: ConnectionState = .disconnected
    var error: Error?

    private let sessionId: UUID
    private let supabaseService: SupabaseService
    private let websocketService: RelayWebSocketService

    private var seenEventIds = Set<String>()
    private var eventStreamTask: Task<Void, Never>?

    init(
        sessionId: UUID,
        supabaseService: SupabaseService = .shared,
        websocketService: RelayWebSocketService = .shared
    ) {
        self.sessionId = sessionId
        self.supabaseService = supabaseService
        self.websocketService = websocketService
    }

    /// Cleanup: Cancel any running tasks when the view model is deallocated
    func cleanup() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
    }

    // MARK: - Cold Path

    func loadSessionCold() async {
        isLoadingCold = true
        error = nil

        defer { isLoadingCold = false }

        do {
            Config.log("❄️ Cold loading session \(sessionId)")

            // Fetch session metadata
            session = try await supabaseService.fetchSession(sessionId)

            // Fetch historical events (last 100)
            let historicalEvents = try await supabaseService.fetchEvents(
                sessionId: sessionId,
                limit: 100,
                orderBy: .descending
            )

            // Store in local state (chronological order)
            events = historicalEvents.reversed()
            seenEventIds = Set(events.map { $0.eventId })

            Config.log("✅ Cold loaded \(events.count) events")

        } catch {
            self.error = error
            Config.log("❌ Failed to cold load session: \(error)")
        }
    }

    // MARK: - Hot Path

    func subscribeHot() async {
        connectionState = .connecting

        do {
            Config.log("🔥 Hot subscribing to session \(sessionId)")

            // Connect WebSocket
            try await websocketService.connect()

            // Authenticate
            guard let token = AuthenticationService.shared.deviceToken,
                  let deviceId = AuthenticationService.shared.deviceId else {
                throw RelayError.authenticationFailed("No credentials available")
            }

            try await websocketService.authenticate(token: token, deviceId: deviceId)

            // Subscribe to session
            try await websocketService.subscribe(sessionId: sessionId.uuidString)

            connectionState = .connected

            Config.log("✅ Hot connected to session \(sessionId)")

            // Start listening for events
            startEventStream()

        } catch {
            connectionState = .failed(error)
            self.error = error
            Config.log("❌ Failed to hot subscribe: \(error)")

            // Retry with exponential backoff
            try? await Task.sleep(for: .seconds(5))
            await subscribeHot()
        }
    }

    private func startEventStream() {
        eventStreamTask = Task {
            guard let eventStream = await websocketService.eventStream else {
                Config.log("⚠️ No event stream available")
                return
            }

            for await event in eventStream {
                await handleHotEvent(event)
            }
        }
    }

    private func handleHotEvent(_ relayEvent: RelayEvent) {
        switch relayEvent {
        case .conversationEvent(let event):
            // Deduplicate: Skip if already seen from cold load
            guard !seenEventIds.contains(event.eventId) else {
                Config.log("⏭️ Skipping duplicate event: \(event.eventId)")
                return
            }

            Config.log("📨 New event received: \(event.type.rawValue)")

            // Append new event
            events.append(event)
            seenEventIds.insert(event.eventId)

            // Update session state if needed
            if case .sessionStateChanged = event.type {
                Task {
                    await refreshSessionMetadata()
                }
            }

        case .error(let code, let message):
            error = RelayError.serverError(code: code, message: message)
            Config.log("❌ Relay error: \(code) - \(message)")

        case .subscribed(let sessionId):
            Config.log("✅ Successfully subscribed to session \(sessionId)")

        case .authSuccess(let deviceId, let accountId):
            Config.log("✅ Authenticated as device \(deviceId)")
            AuthenticationService.shared.saveAccountId(accountId)

        case .authFailure(let reason):
            error = RelayError.authenticationFailed(reason)
            connectionState = .failed(RelayError.authenticationFailed(reason))
            Config.log("❌ Authentication failed: \(reason)")

        case .sessionJoined(let sessionId):
            Config.log("✅ Joined session \(sessionId)")
        }
    }

    private func refreshSessionMetadata() async {
        do {
            session = try await supabaseService.fetchSession(sessionId)
            Config.log("🔄 Refreshed session metadata")
        } catch {
            Config.log("⚠️ Failed to refresh session metadata: \(error)")
        }
    }

    // MARK: - Cleanup

    func unsubscribe() async {
        Config.log("🔌 Unsubscribing from session \(sessionId)")

        eventStreamTask?.cancel()
        eventStreamTask = nil

        do {
            try await websocketService.unsubscribe(sessionId: sessionId.uuidString)
            try await websocketService.disconnect()
        } catch {
            Config.log("⚠️ Error during unsubscribe: \(error)")
        }

        connectionState = .disconnected
    }

    // MARK: - Pagination

    func loadMoreEvents() async {
        guard let firstEvent = events.first else { return }

        do {
            let olderEvents = try await supabaseService.fetchEventsPaginated(
                sessionId: sessionId,
                afterEventId: firstEvent.eventId,
                limit: 50
            )

            // Prepend older events
            events.insert(contentsOf: olderEvents, at: 0)
            seenEventIds.formUnion(olderEvents.map { $0.eventId })

            Config.log("📥 Loaded \(olderEvents.count) more events")
        } catch {
            Config.log("⚠️ Failed to load more events: \(error)")
        }
    }

    // MARK: - Filtering

    func filterEvents(by category: EventCategory) -> [ConversationEvent] {
        events.filter { $0.type.category == category }
    }

    func searchEvents(query: String) -> [ConversationEvent] {
        guard !query.isEmpty else { return events }

        return events.filter { event in
            event.type.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
}
