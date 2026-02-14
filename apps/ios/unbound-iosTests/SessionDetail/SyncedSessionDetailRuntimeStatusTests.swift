import Foundation
import XCTest

@testable import unbound_ios

final class SyncedSessionDetailRuntimeStatusTests: XCTestCase {
    func testRuntimeStatusTransitionsDriveViewModelStatusAndActions() async {
        let loader = StaticSessionDetailMessageLoader()
        let runtimeStatusService = MockRuntimeStatusService()
        let remoteCommandService = makeRemoteCommandService()
        let session = makeSession(deviceId: UUID().uuidString.lowercased())
        let sessionId = await MainActor.run { session.id.uuidString.lowercased() }

        let viewModel = await MainActor.run {
            SyncedSessionDetailViewModel(
                session: session,
                messageService: loader,
                runtimeStatusService: runtimeStatusService,
                remoteCommandService: remoteCommandService
            )
        }

        await viewModel.start()

        await MainActor.run {
            XCTAssertEqual(viewModel.codingSessionStatus, .notAvailable)
            XCTAssertFalse(viewModel.canSendMessage)
            XCTAssertFalse(viewModel.canStopClaude)
            XCTAssertNil(viewModel.codingSessionErrorMessage)
        }

        runtimeStatusService.emit(
            envelope(
                status: .running,
                updatedAtMs: 100,
                sessionId: sessionId
            )
        )
        await waitForStatus(on: viewModel, expected: .running)

        await MainActor.run {
            XCTAssertTrue(viewModel.canSendMessage)
            XCTAssertTrue(viewModel.canStopClaude)
            XCTAssertNil(viewModel.codingSessionErrorMessage)
        }

        runtimeStatusService.emit(
            envelope(
                status: .error,
                updatedAtMs: 200,
                errorMessage: "daemon crashed",
                sessionId: sessionId
            )
        )
        await waitForStatus(on: viewModel, expected: .error)

        await MainActor.run {
            XCTAssertEqual(viewModel.codingSessionErrorMessage, "daemon crashed")
            XCTAssertFalse(viewModel.canStopClaude)
        }

        runtimeStatusService.emit(
            envelope(
                status: .idle,
                updatedAtMs: 300,
                sessionId: sessionId
            )
        )
        await waitForStatus(on: viewModel, expected: .idle)

        await MainActor.run {
            XCTAssertNil(viewModel.codingSessionErrorMessage)
            XCTAssertTrue(viewModel.canSendMessage)
            XCTAssertFalse(viewModel.canStopClaude)
        }

        // Stale update should be ignored due updated_at_ms ordering.
        runtimeStatusService.emit(
            envelope(
                status: .waiting,
                updatedAtMs: 250,
                sessionId: sessionId
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run {
            XCTAssertEqual(viewModel.codingSessionStatus, .idle)
        }

        await MainActor.run {
            viewModel.stopRealtimeUpdates()
        }
    }

    private func waitForStatus(
        on viewModel: SyncedSessionDetailViewModel,
        expected: SessionDetailRuntimeStatus,
        timeoutNs: UInt64 = 2_000_000_000
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNs {
            let current = await MainActor.run { viewModel.codingSessionStatus }
            if current == expected {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for status=\(expected.rawValue)")
    }

    private func makeRemoteCommandService() -> RemoteCommandService {
        RemoteCommandService(
            transport: NoopRemoteCommandTransport(),
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            }
        )
    }

    private func makeSession(deviceId: String?) -> SyncedSession {
        SyncedSession(
            from: SessionRecord(
                id: UUID().uuidString,
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

    private func envelope(
        status: SessionDetailRuntimeStatus,
        updatedAtMs: Int64,
        errorMessage: String? = nil,
        sessionId: String
    ) -> SessionDetailRuntimeStatusEnvelope {
        SessionDetailRuntimeStatusEnvelope(
            schemaVersion: 1,
            codingSession: SessionDetailRuntimeState(status: status, errorMessage: errorMessage),
            deviceId: "11111111-1111-1111-1111-111111111111",
            sessionId: sessionId,
            updatedAtMs: updatedAtMs
        )
    }
}

private final class StaticSessionDetailMessageLoader: SessionDetailMessageLoading {
    func loadMessages(sessionId _: UUID) async throws -> SessionDetailLoadResult {
        SessionDetailLoadResult(messages: [], decryptedMessageCount: 0)
    }

    func messageUpdates(sessionId _: UUID) -> AsyncThrowingStream<SessionDetailLoadResult, Error> {
        AsyncThrowingStream { _ in }
    }
}

private final class MockRuntimeStatusService: SessionDetailRuntimeStatusStreaming {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<SessionDetailRuntimeStatusEnvelope, Error>.Continuation?
    private var pending: [SessionDetailRuntimeStatusEnvelope] = []

    func subscribe(sessionId _: UUID) -> AsyncThrowingStream<SessionDetailRuntimeStatusEnvelope, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            self.continuation = continuation
            let buffered = pending
            pending.removeAll()
            lock.unlock()

            for envelope in buffered {
                continuation.yield(envelope)
            }
        }
    }

    func emit(_ envelope: SessionDetailRuntimeStatusEnvelope) {
        lock.lock()
        let continuation = self.continuation
        if continuation == nil {
            pending.append(envelope)
        }
        lock.unlock()

        continuation?.yield(envelope)
    }
}

private final class NoopRemoteCommandTransport: RemoteCommandTransport {
    private var lastType: String?

    func publishRemoteCommand(
        channel _: String,
        payload _: UMSecretRequestCommandPayload
    ) async throws {}

    func waitForAck(
        channel _: String,
        requestId: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandAckEnvelope {
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
        lastType = envelope.type
    }

    func waitForCommandResponse(
        channel _: String,
        requestId: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandResponse {
        if lastType == "gh.pr.list.v1" {
            return RemoteCommandResponse(
                schemaVersion: 1,
                requestId: requestId,
                type: "gh.pr.list.v1",
                status: "ok",
                result: .object([
                    "pull_requests": .array([]),
                    "count": .int(0),
                ]),
                errorCode: nil,
                errorMessage: nil,
                createdAtMs: 1
            )
        }

        return RemoteCommandResponse(
            schemaVersion: 1,
            requestId: requestId,
            type: lastType ?? "mock.v1",
            status: "ok",
            result: .object([:]),
            errorCode: nil,
            errorMessage: nil,
            createdAtMs: 1
        )
    }
}
