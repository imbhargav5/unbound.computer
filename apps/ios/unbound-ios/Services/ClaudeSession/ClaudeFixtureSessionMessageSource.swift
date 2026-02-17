import ClaudeConversationTimeline
import Foundation

final class ClaudeFixtureSessionMessageSource: ClaudeSessionMessageSource {
    private let loader: SessionDetailFixtureMessageLoader

    var isDeviceSource: Bool { false }

    init(loader: SessionDetailFixtureMessageLoader) {
        self.loader = loader
    }

    func loadInitial(sessionId _: UUID) async throws -> [RawSessionRow] {
        let fixture = try loader.loadFixture()
        return fixture.messages.map { message in
            RawSessionRow(
                id: message.id,
                sequenceNumber: message.sequenceNumber,
                createdAt: message.timestamp,
                updatedAt: nil,
                payload: message.content
            )
        }
    }

    func stream(sessionId _: UUID) -> AsyncThrowingStream<RawSessionRow, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
