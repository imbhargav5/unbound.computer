import Foundation
import XCTest

@testable import unbound_ios

final class SyncedSessionDetailViewModelTests: XCTestCase {
    func testLoadMessagesSuccessUpdatesState() async {
        let expectedMessage = Message(
            id: UUID(),
            content: "hello",
            role: .assistant,
            timestamp: Date(timeIntervalSince1970: 1),
            isStreaming: false
        )
        let loader = MockSessionDetailMessageLoader(
            result: .success(
                SessionDetailLoadResult(messages: [expectedMessage], decryptedMessageCount: 1)
            )
        )

        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: makeSession(),
                messageService: loader
            )
        }

        await viewModel.loadMessages()

        await MainActor.run {
            XCTAssertEqual(viewModel.messages.count, 1)
            XCTAssertEqual(viewModel.messages.first?.content, "hello")
            XCTAssertEqual(viewModel.decryptedMessageCount, 1)
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertFalse(viewModel.isLoading)
        }
        XCTAssertEqual(loader.calls, 1)
    }

    func testLoadMessagesFailureSetsErrorMessage() async {
        let loader = MockSessionDetailMessageLoader(result: .failure(SessionDetailMessageError.fetchFailed))
        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: makeSession(),
                messageService: loader
            )
        }

        await viewModel.loadMessages()

        await MainActor.run {
            XCTAssertEqual(viewModel.messages.count, 0)
            XCTAssertNotNil(viewModel.errorMessage)
        }
        XCTAssertEqual(loader.calls, 1)
    }

    func testLoadMessagesRespectsForceReload() async {
        let loader = MockSessionDetailMessageLoader(
            result: .success(SessionDetailLoadResult(messages: [], decryptedMessageCount: 0))
        )
        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: makeSession(),
                messageService: loader
            )
        }

        await viewModel.loadMessages()
        await viewModel.loadMessages()
        await viewModel.loadMessages(force: true)

        XCTAssertEqual(loader.calls, 2)
    }

    func testLoadMessagesWithFixtureLoaderProducesRenderableMessages() async throws {
        let fixtureLoader = SessionDetailFixtureMessageLoader(fixtureURL: fixtureURL())
        let fixture = try fixtureLoader.loadFixture()
        let session = makeSession(id: fixture.session.id)

        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: session,
                messageService: fixtureLoader
            )
        }

        await viewModel.loadMessages()

        await MainActor.run {
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertFalse(viewModel.messages.isEmpty)
            XCTAssertEqual(viewModel.decryptedMessageCount, fixture.messages.count)
        }
    }

    func testStartConsumesRealtimeUpdatesFromService() async {
        let initial = Message(
            id: UUID(),
            content: "initial",
            role: .assistant,
            timestamp: Date(timeIntervalSince1970: 1),
            isStreaming: false
        )
        let realtime = Message(
            id: UUID(),
            content: "realtime",
            role: .assistant,
            timestamp: Date(timeIntervalSince1970: 2),
            isStreaming: false
        )
        let loader = MockSessionDetailMessageLoader(
            result: .success(
                SessionDetailLoadResult(messages: [initial], decryptedMessageCount: 1)
            )
        )

        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: makeSession(),
                messageService: loader
            )
        }

        await viewModel.start()
        loader.emitUpdate(
            SessionDetailLoadResult(
                messages: [initial, realtime],
                decryptedMessageCount: 2
            )
        )

        for _ in 0..<50 {
            let currentCount = await MainActor.run { viewModel.messages.count }
            if currentCount == 2 {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        await MainActor.run {
            XCTAssertEqual(viewModel.messages.count, 2)
            XCTAssertEqual(viewModel.messages.last?.content, "realtime")
            XCTAssertEqual(viewModel.decryptedMessageCount, 2)
        }
        XCTAssertEqual(loader.calls, 1)
        XCTAssertEqual(loader.updateCalls, 1)
    }

    private func makeSession(id: String = UUID().uuidString) -> SyncedSession {
        SyncedSession(
            from: SessionRecord(
                id: id,
                repositoryId: UUID().uuidString,
                title: "Session",
                claudeSessionId: nil,
                isWorktree: false,
                worktreePath: nil,
                status: "active",
                createdAt: Date(timeIntervalSince1970: 1),
                lastAccessedAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )
    }

    private func fixtureURL() -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return repositoryRoot
            .appendingPathComponent("apps/ios/unbound-ios/Resources/PreviewFixtures/session-detail-max-messages.json")
    }
}

private final class MockSessionDetailMessageLoader: SessionDetailMessageLoading {
    private let result: Result<SessionDetailLoadResult, Error>
    private(set) var calls = 0
    private(set) var updateCalls = 0
    private var continuation: AsyncThrowingStream<SessionDetailLoadResult, Error>.Continuation?
    private var bufferedUpdates: [SessionDetailLoadResult] = []

    init(result: Result<SessionDetailLoadResult, Error>) {
        self.result = result
    }

    func loadMessages(sessionId _: UUID) async throws -> SessionDetailLoadResult {
        calls += 1
        return try result.get()
    }

    func messageUpdates(sessionId _: UUID) -> AsyncThrowingStream<SessionDetailLoadResult, Error> {
        updateCalls += 1
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            for update in self.bufferedUpdates {
                continuation.yield(update)
            }
            self.bufferedUpdates.removeAll()
        }
    }

    func emitUpdate(_ update: SessionDetailLoadResult) {
        if let continuation {
            continuation.yield(update)
        } else {
            bufferedUpdates.append(update)
        }
    }
}
