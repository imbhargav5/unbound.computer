import ClaudeConversationTimeline
import Foundation
import Logging

private let claudeLocalLogger = Logger(label: "app.claude.local-session-message-source")

final class ClaudeLocalSessionMessageSource: ClaudeSessionMessageSource {
    private let daemonClient: DaemonClient
    private let streamingClientFactory: (String) -> SessionStreamingClient

    var isDeviceSource: Bool { true }

    init(
        daemonClient: DaemonClient = .shared,
        streamingClientFactory: @escaping (String) -> SessionStreamingClient = { SessionStreamingClient(sessionId: $0) }
    ) {
        self.daemonClient = daemonClient
        self.streamingClientFactory = streamingClientFactory
    }

    func loadInitial(sessionId: UUID) async throws -> [RawSessionRow] {
        let messages = try await daemonClient.listMessages(sessionId: sessionId.uuidString)
        return messages.compactMap(ClaudeLocalSessionRowNormalizer.fromDaemonMessage(_:))
    }

    func stream(sessionId: UUID) -> AsyncThrowingStream<RawSessionRow, Error> {
        AsyncThrowingStream { continuation in
            let client = streamingClientFactory(sessionId.uuidString)
            let task = Task {
                do {
                    let events = try await client.subscribe()
                    for await event in events {
                        guard let row = ClaudeLocalSessionRowNormalizer.fromDaemonEvent(event) else {
                            continue
                        }
                        continuation.yield(row)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    claudeLocalLogger.error(
                        "Claude local stream failed for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
                    )
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                client.disconnect()
            }
        }
    }
}

private enum ClaudeLocalSessionRowNormalizer {
    static func fromDaemonMessage(_ message: DaemonMessage) -> RawSessionRow? {
        guard let content = message.content else { return nil }
        return RawSessionRow(
            id: message.id,
            sequenceNumber: message.sequenceNumber,
            createdAt: message.date,
            updatedAt: nil,
            payload: content
        )
    }

    static func fromDaemonEvent(_ event: DaemonEvent) -> RawSessionRow? {
        guard let raw = event.rawClaudeEvent else { return nil }
        return RawSessionRow(
            id: "event-\(event.sequence)",
            sequenceNumber: Int(event.sequence),
            createdAt: nil,
            updatedAt: nil,
            payload: raw
        )
    }
}
