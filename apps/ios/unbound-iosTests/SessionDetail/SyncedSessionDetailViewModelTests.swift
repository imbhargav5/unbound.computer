import Foundation
import XCTest

@testable import unbound_ios

final class SyncedSessionDetailViewModelTests: XCTestCase {
    private static let retainedServicesLock = NSLock()
    private static var retainedRemoteCommandServices: [RemoteCommandService] = []

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

        for _ in 0..<200 {
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

    func testRefreshPullRequestsLoadsAndSelectsFirst() async {
        let transport = MockGenericRemoteCommandTransport()
        transport.resultByType["gh.pr.list.v1"] = [
            "pull_requests": .array([
                .object([
                    "number": .int(42),
                    "title": .string("Add bakugou crate"),
                    "url": .string("https://github.com/unbound/repo/pull/42"),
                    "state": .string("OPEN"),
                    "is_draft": .bool(false),
                ]),
                .object([
                    "number": .int(43),
                    "title": .string("Wire gh IPC"),
                    "url": .string("https://github.com/unbound/repo/pull/43"),
                    "state": .string("OPEN"),
                    "is_draft": .bool(false),
                ]),
            ]),
            "count": .int(2),
        ]
        transport.resultByType["gh.pr.checks.v1"] = [
            "checks": .array([
                .object([
                    "name": .string("CI"),
                    "state": .string("completed"),
                    "bucket": .string("pass"),
                ]),
            ]),
            "summary": .object([
                "total": .int(1),
                "passing": .int(1),
                "failing": .int(0),
                "pending": .int(0),
                "skipped": .int(0),
                "cancelled": .int(0),
            ]),
        ]

        let loader = MockSessionDetailMessageLoader(
            result: .success(SessionDetailLoadResult(messages: [], decryptedMessageCount: 0))
        )
        let service = makeRetainedRemoteCommandService(transport: transport)
        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: makeSession(deviceId: UUID().uuidString.lowercased()),
                messageService: loader,
                remoteCommandService: service
            )
        }

        await viewModel.refreshPullRequests()

        await MainActor.run {
            XCTAssertEqual(viewModel.pullRequests.count, 2)
            XCTAssertEqual(viewModel.selectedPullRequest?.number, 42)
            XCTAssertEqual(viewModel.selectedPullRequestChecks?.summary.total, 1)
            XCTAssertNil(viewModel.commandError)
        }
        XCTAssertEqual(transport.publishedEnvelopes.map(\.type), ["gh.pr.list.v1", "gh.pr.checks.v1"])
    }

    func testCreatePullRequestClearsDraftFieldsOnSuccess() async {
        let transport = MockGenericRemoteCommandTransport()
        transport.resultByType["gh.pr.create.v1"] = [
            "url": .string("https://github.com/unbound/repo/pull/44"),
            "pull_request": .object([
                "number": .int(44),
                "title": .string("Create from iOS"),
                "url": .string("https://github.com/unbound/repo/pull/44"),
                "state": .string("OPEN"),
                "is_draft": .bool(false),
            ]),
        ]
        transport.resultByType["gh.pr.list.v1"] = [
            "pull_requests": .array([
                .object([
                    "number": .int(44),
                    "title": .string("Create from iOS"),
                    "url": .string("https://github.com/unbound/repo/pull/44"),
                    "state": .string("OPEN"),
                    "is_draft": .bool(false),
                ]),
            ]),
            "count": .int(1),
        ]
        transport.resultByType["gh.pr.checks.v1"] = [
            "checks": .array([]),
            "summary": .object([
                "total": .int(0),
                "passing": .int(0),
                "failing": .int(0),
                "pending": .int(0),
                "skipped": .int(0),
                "cancelled": .int(0),
            ]),
        ]

        let loader = MockSessionDetailMessageLoader(
            result: .success(SessionDetailLoadResult(messages: [], decryptedMessageCount: 0))
        )
        let service = makeRetainedRemoteCommandService(transport: transport)
        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: makeSession(deviceId: UUID().uuidString.lowercased()),
                messageService: loader,
                remoteCommandService: service
            )
        }

        await MainActor.run {
            viewModel.prTitle = "Create from iOS"
            viewModel.prBody = "PR body"
        }
        await viewModel.createPullRequest()

        await MainActor.run {
            XCTAssertEqual(viewModel.selectedPullRequest?.number, 44)
            XCTAssertTrue(viewModel.prTitle.isEmpty)
            XCTAssertTrue(viewModel.prBody.isEmpty)
            XCTAssertFalse(viewModel.isCreatingPullRequest)
            XCTAssertNil(viewModel.commandError)
        }
        XCTAssertTrue(transport.publishedEnvelopes.map(\.type).contains("gh.pr.create.v1"))
    }

    func testMergePullRequestFailureSetsCommandError() async {
        let transport = MockGenericRemoteCommandTransport()
        transport.resultByType["gh.pr.list.v1"] = [
            "pull_requests": .array([
                .object([
                    "number": .int(45),
                    "title": .string("Merge test"),
                    "url": .string("https://github.com/unbound/repo/pull/45"),
                    "state": .string("OPEN"),
                    "is_draft": .bool(false),
                ]),
            ]),
            "count": .int(1),
        ]
        transport.resultByType["gh.pr.checks.v1"] = [
            "checks": .array([]),
            "summary": .object([
                "total": .int(0),
                "passing": .int(0),
                "failing": .int(0),
                "pending": .int(0),
                "skipped": .int(0),
                "cancelled": .int(0),
            ]),
        ]
        transport.errorByType["gh.pr.merge.v1"] = (
            code: "gh_not_authenticated",
            message: "run gh auth login"
        )

        let loader = MockSessionDetailMessageLoader(
            result: .success(SessionDetailLoadResult(messages: [], decryptedMessageCount: 0))
        )
        let service = makeRetainedRemoteCommandService(transport: transport)
        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: makeSession(deviceId: UUID().uuidString.lowercased()),
                messageService: loader,
                remoteCommandService: service
            )
        }

        await viewModel.refreshPullRequests()
        await viewModel.mergeSelectedPullRequest()

        await MainActor.run {
            XCTAssertFalse(viewModel.isMergingPullRequest)
            XCTAssertNotNil(viewModel.commandError)
            XCTAssertTrue(viewModel.commandError?.contains("gh_not_authenticated") ?? false)
        }
        XCTAssertTrue(transport.publishedEnvelopes.map(\.type).contains("gh.pr.merge.v1"))
    }

    private func makeSession(
        id: String = UUID().uuidString,
        deviceId: String? = nil
    ) -> SyncedSession {
        SyncedSession(
            from: SessionRecord(
                id: id,
                repositoryId: UUID().uuidString,
                title: "Session",
                claudeSessionId: nil,
                isWorktree: false,
                worktreePath: nil,
                status: "active",
                deviceId: deviceId,
                createdAt: Date(timeIntervalSince1970: 1),
                lastAccessedAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )
    }

    private func makeRemoteCommandService(
        transport: RemoteCommandTransport
    ) -> RemoteCommandService {
        RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            }
        )
    }

    private func makeRetainedRemoteCommandService(
        transport: RemoteCommandTransport
    ) -> RemoteCommandService {
        let service = makeRemoteCommandService(transport: transport)
        Self.retainedServicesLock.lock()
        Self.retainedRemoteCommandServices.append(service)
        Self.retainedServicesLock.unlock()
        return service
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
    private let stateLock = NSLock()
    private(set) var calls = 0
    private(set) var updateCalls = 0
    private var continuation: AsyncThrowingStream<SessionDetailLoadResult, Error>.Continuation?
    private var bufferedUpdates: [SessionDetailLoadResult] = []

    init(result: Result<SessionDetailLoadResult, Error>) {
        self.result = result
    }

    func loadMessages(sessionId _: UUID) async throws -> SessionDetailLoadResult {
        stateLock.lock()
        calls += 1
        stateLock.unlock()
        return try result.get()
    }

    func messageUpdates(sessionId _: UUID) -> AsyncThrowingStream<SessionDetailLoadResult, Error> {
        stateLock.lock()
        updateCalls += 1
        stateLock.unlock()
        return AsyncThrowingStream { continuation in
            self.stateLock.lock()
            self.continuation = continuation
            let pendingUpdates = self.bufferedUpdates
            self.bufferedUpdates.removeAll()
            self.stateLock.unlock()

            for update in pendingUpdates {
                continuation.yield(update)
            }
        }
    }

    func emitUpdate(_ update: SessionDetailLoadResult) {
        stateLock.lock()
        let currentContinuation = continuation
        if currentContinuation == nil {
            bufferedUpdates.append(update)
        }
        stateLock.unlock()

        currentContinuation?.yield(update)
    }
}

private final class MockGenericRemoteCommandTransport: RemoteCommandTransport {
    var publishedEnvelopes: [RemoteCommandEnvelope] = []
    var resultByType: [String: [String: AnyCodableValue]] = [:]
    var errorByType: [String: (code: String?, message: String?)] = [:]
    var publishError: Error?
    var ackError: Error?
    var responseError: Error?

    func publishRemoteCommand(
        channel _: String,
        payload _: UMSecretRequestCommandPayload
    ) async throws {}

    func waitForAck(
        channel _: String,
        requestId: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandAckEnvelope {
        if let ackError {
            throw ackError
        }

        let decision = RemoteCommandDecisionResult(
            schemaVersion: 1,
            requestId: requestId,
            sessionId: nil,
            status: "accepted",
            reasonCode: nil,
            message: "accepted"
        )
        let encoded = try JSONEncoder().encode(decision).base64EncodedString()

        return RemoteCommandAckEnvelope(
            schemaVersion: 1,
            commandId: UUID().uuidString.lowercased(),
            status: "accepted",
            createdAtMs: 1,
            resultB64: encoded
        )
    }

    func waitForSessionSecretResponse(
        channel _: String,
        requestId _: String,
        sessionId _: String,
        timeout _: TimeInterval
    ) async throws -> SessionSecretResponseEnvelope {
        SessionSecretResponseEnvelope(
            schemaVersion: 1,
            requestId: UUID().uuidString.lowercased(),
            sessionId: UUID().uuidString.lowercased(),
            senderDeviceId: UUID().uuidString.lowercased(),
            receiverDeviceId: UUID().uuidString.lowercased(),
            status: "error",
            errorCode: "not_supported",
            ciphertextB64: nil,
            encapsulationPubkeyB64: nil,
            nonceB64: nil,
            algorithm: "",
            createdAtMs: 1
        )
    }

    func publishGenericCommand(
        channel _: String,
        envelope: RemoteCommandEnvelope
    ) async throws {
        if let publishError {
            throw publishError
        }
        publishedEnvelopes.append(envelope)
    }

    func waitForCommandResponse(
        channel _: String,
        requestId: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandResponse {
        if let responseError {
            throw responseError
        }

        let type = publishedEnvelopes.last?.type ?? "mock.v1"
        if let err = errorByType[type] {
            return RemoteCommandResponse(
                schemaVersion: 1,
                requestId: requestId,
                type: type,
                status: "error",
                result: nil,
                errorCode: err.code,
                errorMessage: err.message,
                createdAtMs: 1
            )
        }

        return RemoteCommandResponse(
            schemaVersion: 1,
            requestId: requestId,
            type: type,
            status: "ok",
            result: resultByType[type].map(AnyCodableValue.object),
            errorCode: nil,
            errorMessage: nil,
            createdAtMs: 1
        )
    }
}
