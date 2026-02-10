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

    private func makeSession() -> SyncedSession {
        SyncedSession(
            from: SessionRecord(
                id: UUID().uuidString,
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
}

private final class MockSessionDetailMessageLoader: SessionDetailMessageLoading {
    private let result: Result<SessionDetailLoadResult, Error>
    private(set) var calls = 0

    init(result: Result<SessionDetailLoadResult, Error>) {
        self.result = result
    }

    func loadMessages(sessionId _: UUID) async throws -> SessionDetailLoadResult {
        calls += 1
        return try result.get()
    }
}
