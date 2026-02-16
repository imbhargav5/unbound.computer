import Foundation
import XCTest

@testable import unbound_ios

final class RemoteCommandEnvelopeTests: XCTestCase {
    func testEnvelopeSerializesWithSnakeCaseKeys() throws {
        let envelope = RemoteCommandEnvelope(
            schemaVersion: 1,
            type: "session.create.v1",
            requestId: "11111111-1111-1111-1111-111111111111",
            requesterDeviceId: "22222222-2222-2222-2222-222222222222",
            targetDeviceId: "33333333-3333-3333-3333-333333333333",
            requestedAtMs: 1700000000000,
            params: ["repository_id": .string("repo-1")]
        )

        let data = try JSONEncoder().encode(envelope)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["schema_version"] as? Int, 1)
        XCTAssertEqual(dict["type"] as? String, "session.create.v1")
        XCTAssertEqual(dict["request_id"] as? String, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(dict["requester_device_id"] as? String, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(dict["target_device_id"] as? String, "33333333-3333-3333-3333-333333333333")
        XCTAssertEqual(dict["requested_at_ms"] as? Int64, 1700000000000)
        XCTAssertNotNil(dict["params"])

        // Verify camelCase keys are NOT present
        XCTAssertNil(dict["schemaVersion"])
        XCTAssertNil(dict["requestId"])
        XCTAssertNil(dict["requesterDeviceId"])
        XCTAssertNil(dict["targetDeviceId"])
        XCTAssertNil(dict["requestedAtMs"])
    }

    func testEnvelopeRoundTrip() throws {
        let original = RemoteCommandEnvelope(
            schemaVersion: 1,
            type: "claude.send.v1",
            requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            requesterDeviceId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            targetDeviceId: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            requestedAtMs: 1700000000000,
            params: [
                "session_id": .string("session-1"),
                "content": .string("hello world"),
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteCommandEnvelope.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, original.schemaVersion)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.requestId, original.requestId)
        XCTAssertEqual(decoded.requesterDeviceId, original.requesterDeviceId)
        XCTAssertEqual(decoded.targetDeviceId, original.targetDeviceId)
        XCTAssertEqual(decoded.requestedAtMs, original.requestedAtMs)
        XCTAssertEqual(decoded.params["session_id"], .string("session-1"))
        XCTAssertEqual(decoded.params["content"], .string("hello world"))
    }

    func testEnvelopeSupportsGhCommandType() throws {
        let original = RemoteCommandEnvelope(
            schemaVersion: 1,
            type: "gh.pr.list.v1",
            requestId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            requesterDeviceId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            targetDeviceId: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            requestedAtMs: 1700000000000,
            params: [
                "session_id": .string("session-1"),
                "state": .string("open"),
                "limit": .int(20),
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteCommandEnvelope.self, from: data)

        XCTAssertEqual(decoded.type, "gh.pr.list.v1")
        XCTAssertEqual(decoded.params["session_id"], .string("session-1"))
        XCTAssertEqual(decoded.params["state"], .string("open"))
        XCTAssertEqual(decoded.params["limit"], .int(20))
    }
}

final class RemoteCommandResponseTests: XCTestCase {
    func testResponseDeserializesFromSnakeCaseJSON() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-abc",
            "type": "session.create.v1",
            "status": "ok",
            "result": {
                "id": "session-123",
                "repository_id": "repo-456",
                "title": "New Session",
                "status": "active"
            },
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)

        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.requestId, "req-abc")
        XCTAssertEqual(response.type, "session.create.v1")
        XCTAssertEqual(response.status, "ok")
        XCTAssertTrue(response.isOk)
        XCTAssertNil(response.errorCode)
        XCTAssertNil(response.errorMessage)
        XCTAssertEqual(response.createdAtMs, 1700000000000)

        let result = response.result?.objectValue
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["id"]?.stringValue, "session-123")
        XCTAssertEqual(result?["repository_id"]?.stringValue, "repo-456")
    }

    func testResponseIsOkReturnsFalseForError() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-err",
            "type": "claude.send.v1",
            "status": "error",
            "error_code": "invalid_params",
            "error_message": "session_id is required",
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)

        XCTAssertFalse(response.isOk)
        XCTAssertEqual(response.errorCode, "invalid_params")
        XCTAssertEqual(response.errorMessage, "session_id is required")
        XCTAssertNil(response.result)
    }

    func testResponseDecodesOptionalErrorData() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-err-data",
            "type": "session.create.v1",
            "status": "error",
            "error_code": "setup_hook_failed",
            "error_message": "setup hook failed",
            "error_data": {
                "stage": "post_create",
                "stderr": "command failed"
            },
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)
        XCTAssertEqual(response.errorCode, "setup_hook_failed")
        XCTAssertEqual(response.errorData?.objectValue?["stage"], .string("post_create"))
        XCTAssertEqual(response.errorData?.objectValue?["stderr"], .string("command failed"))
    }

    func testResponseDecodesScalarErrorData() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-err-scalar",
            "type": "session.create.v1",
            "status": "error",
            "error_code": "setup_hook_failed",
            "error_message": "setup hook failed",
            "error_data": "hook timeout",
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)
        XCTAssertEqual(response.errorCode, "setup_hook_failed")
        XCTAssertEqual(response.errorData, .string("hook timeout"))
    }

    func testResponseDecodesArrayErrorData() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-err-array",
            "type": "session.create.v1",
            "status": "error",
            "error_code": "setup_hook_failed",
            "error_message": "setup hook failed",
            "error_data": ["timeout", 30, true],
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)
        XCTAssertEqual(response.errorCode, "setup_hook_failed")
        XCTAssertEqual(response.errorData, .array([.string("timeout"), .int(30), .bool(true)]))
    }

    func testResponseDecodesNumericErrorData() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-err-num",
            "type": "session.create.v1",
            "status": "error",
            "error_code": "setup_hook_failed",
            "error_message": "setup hook failed",
            "error_data": 408,
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)
        XCTAssertEqual(response.errorCode, "setup_hook_failed")
        XCTAssertEqual(response.errorData, .int(408))
    }

    func testResponseDecodesBooleanErrorData() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-err-bool",
            "type": "session.create.v1",
            "status": "error",
            "error_code": "setup_hook_failed",
            "error_message": "setup hook failed",
            "error_data": false,
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)
        XCTAssertEqual(response.errorCode, "setup_hook_failed")
        XCTAssertEqual(response.errorData, .bool(false))
    }

    func testResponseNullErrorDataDecodesAsNil() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-err-null",
            "type": "session.create.v1",
            "status": "error",
            "error_code": "setup_hook_failed",
            "error_message": "setup hook failed",
            "error_data": null,
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)
        XCTAssertEqual(response.errorCode, "setup_hook_failed")
        XCTAssertNil(response.errorData)
    }

    func testResponseDecodesNestedObjectErrorData() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-err-nested",
            "type": "session.create.v1",
            "status": "error",
            "error_code": "setup_hook_failed",
            "error_message": "setup hook failed",
            "error_data": {
                "details": {
                    "kind": "timeout",
                    "seconds": 300
                },
                "retryable": true
            },
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)
        XCTAssertEqual(response.errorCode, "setup_hook_failed")
        XCTAssertEqual(response.errorData?.objectValue?["retryable"], .bool(true))
        XCTAssertEqual(
            response.errorData?.objectValue?["details"]?.objectValue?["seconds"],
            .int(300)
        )
    }

    func testResponseWithNullableFieldsOmitted() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-min",
            "type": "claude.stop.v1",
            "status": "ok",
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)

        XCTAssertTrue(response.isOk)
        XCTAssertNil(response.result)
        XCTAssertNil(response.errorCode)
        XCTAssertNil(response.errorMessage)
    }

    func testResponseDecodesGhPrListPayload() throws {
        let json = """
        {
            "schema_version": 1,
            "request_id": "req-gh-list",
            "type": "gh.pr.list.v1",
            "status": "ok",
            "result": {
                "pull_requests": [
                    {
                        "number": 42,
                        "title": "Add gh integration",
                        "url": "https://github.com/unbound/repo/pull/42",
                        "state": "OPEN",
                        "is_draft": false
                    }
                ],
                "count": 1
            },
            "created_at_ms": 1700000000000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteCommandResponse.self, from: json)
        XCTAssertTrue(response.isOk)
        let result = response.result?.objectValue
        XCTAssertEqual(result?["count"]?.intValue, 1)
        let prs = result?["pull_requests"]?.arrayValue
        XCTAssertEqual(prs?.count, 1)
        XCTAssertEqual(prs?.first?.objectValue?["number"]?.intValue, 42)
    }
}

final class AnyCodableValueTests: XCTestCase {
    func testStringRoundTrip() throws {
        let value = AnyCodableValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, .string("hello"))
    }

    func testBoolRoundTrip() throws {
        let value = AnyCodableValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, .bool(true))
    }

    func testIntRoundTrip() throws {
        let value = AnyCodableValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, .int(42))
    }

    func testObjectRoundTrip() throws {
        let value = AnyCodableValue.object([
            "key": .string("value"),
            "count": .int(5),
            "active": .bool(false),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testArrayRoundTrip() throws {
        let value = AnyCodableValue.array([.string("a"), .int(1), .bool(true)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testNullRoundTrip() throws {
        let value = AnyCodableValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, .null)
    }

    func testObjectValueAccessor() {
        let dict: [String: AnyCodableValue] = ["id": .string("abc")]
        let value = AnyCodableValue.object(dict)
        XCTAssertEqual(value.objectValue?["id"]?.stringValue, "abc")
    }

    func testObjectValueReturnsNilForNonObject() {
        let value = AnyCodableValue.string("not an object")
        XCTAssertNil(value.objectValue)
    }

    func testStringValueReturnsNilForNonString() {
        let value = AnyCodableValue.int(42)
        XCTAssertNil(value.stringValue)
    }

    func testNestedObjectRoundTrip() throws {
        let value = AnyCodableValue.object([
            "session": .object([
                "id": .string("sess-1"),
                "active": .bool(true),
            ]),
            "tags": .array([.string("test"), .string("dev")]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }
}

final class RemoteCommandAvailabilityTests: XCTestCase {
    func testCreateSessionFailsWhenTargetDaemonUnavailable() async {
        let service = RemoteCommandService(
            transport: NoopRemoteTransport(),
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .offline }
        )

        do {
            _ = try await service.createSession(
                targetDeviceId: "22222222-2222-2222-2222-222222222222",
                repositoryId: "33333333-3333-3333-3333-333333333333"
            )
            XCTFail("Expected target unavailable error")
        } catch let error as RemoteCommandError {
            switch error {
            case .targetUnavailable(let target):
                XCTAssertEqual(target, "22222222-2222-2222-2222-222222222222")
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCreateSessionAllowsUnknownTargetAvailability() async throws {
        let transport = CapturingRemoteTransport()
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .unknown }
        )

        let result = try await service.createSession(
            targetDeviceId: "22222222-2222-2222-2222-222222222222",
            repositoryId: "33333333-3333-3333-3333-333333333333"
        )

        XCTAssertEqual(result.id, "session-1")
    }
}

final class RemoteCommandCreateSessionPayloadTests: XCTestCase {
    func testCreateSessionMainDirectorySendsIsWorktreeFalse() async throws {
        let transport = CapturingRemoteTransport()
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        _ = try await service.createSession(
            targetDeviceId: "22222222-2222-2222-2222-222222222222",
            repositoryId: "33333333-3333-3333-3333-333333333333",
            isWorktree: false
        )

        let params = transport.publishedEnvelopes.last?.params
        XCTAssertEqual(params?["is_worktree"], .bool(false))
        XCTAssertNil(params?["base_branch"])
    }

    func testCreateSessionWorktreeSendsBaseBranch() async throws {
        let transport = CapturingRemoteTransport()
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        _ = try await service.createSession(
            targetDeviceId: "22222222-2222-2222-2222-222222222222",
            repositoryId: "33333333-3333-3333-3333-333333333333",
            isWorktree: true,
            baseBranch: "main"
        )

        let params = transport.publishedEnvelopes.last?.params
        XCTAssertEqual(params?["is_worktree"], .bool(true))
        XCTAssertEqual(params?["base_branch"], .string("main"))
    }

    func testCreateSessionErrorIncludesStructuredErrorData() async {
        let transport = ErrorResponseRemoteTransport(
            response: RemoteCommandResponse(
                schemaVersion: 1,
                requestId: "req-error",
                type: "session.create.v1",
                status: "error",
                result: nil,
                errorCode: "setup_hook_failed",
                errorMessage: "setup hook failed",
                errorData: .object([
                    "stage": .string("pre_create"),
                    "stderr": .string("hook failed")
                ]),
                createdAtMs: 1
            )
        )
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        do {
            _ = try await service.createSession(
                targetDeviceId: "22222222-2222-2222-2222-222222222222",
                repositoryId: "33333333-3333-3333-3333-333333333333",
                isWorktree: true
            )
            XCTFail("Expected commandFailed error")
        } catch let error as RemoteCommandError {
            switch error {
            case .commandFailed(let errorCode, let errorMessage, let errorData):
                XCTAssertEqual(errorCode, "setup_hook_failed")
                XCTAssertEqual(errorMessage, "setup hook failed")
                XCTAssertEqual(errorData?.objectValue?["stage"], .string("pre_create"))
                XCTAssertEqual(errorData?.objectValue?["stderr"], .string("hook failed"))
            default:
                XCTFail("Unexpected RemoteCommandError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateSessionErrorWithScalarErrorDataStillThrowsCommandFailed() async {
        let transport = ErrorResponseRemoteTransport(
            response: RemoteCommandResponse(
                schemaVersion: 1,
                requestId: "req-error",
                type: "session.create.v1",
                status: "error",
                result: nil,
                errorCode: "setup_hook_failed",
                errorMessage: "setup hook failed",
                errorData: .string("hook timeout"),
                createdAtMs: 1
            )
        )
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        do {
            _ = try await service.createSession(
                targetDeviceId: "22222222-2222-2222-2222-222222222222",
                repositoryId: "33333333-3333-3333-3333-333333333333",
                isWorktree: true
            )
            XCTFail("Expected commandFailed error")
        } catch let error as RemoteCommandError {
            switch error {
            case .commandFailed(let errorCode, let errorMessage, let errorData):
                XCTAssertEqual(errorCode, "setup_hook_failed")
                XCTAssertEqual(errorMessage, "setup hook failed")
                XCTAssertEqual(errorData, .string("hook timeout"))
                XCTAssertEqual(
                    error.localizedDescription,
                    "Command failed (setup_hook_failed): setup hook failed [error_data=hook timeout]"
                )
            default:
                XCTFail("Unexpected RemoteCommandError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateSessionErrorWithArrayErrorDataRendersDetails() async {
        let transport = ErrorResponseRemoteTransport(
            response: RemoteCommandResponse(
                schemaVersion: 1,
                requestId: "req-error-array",
                type: "session.create.v1",
                status: "error",
                result: nil,
                errorCode: "setup_hook_failed",
                errorMessage: "setup hook failed",
                errorData: .array([.string("timeout"), .int(30)]),
                createdAtMs: 1
            )
        )
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        do {
            _ = try await service.createSession(
                targetDeviceId: "22222222-2222-2222-2222-222222222222",
                repositoryId: "33333333-3333-3333-3333-333333333333",
                isWorktree: true
            )
            XCTFail("Expected commandFailed error")
        } catch let error as RemoteCommandError {
            switch error {
            case .commandFailed(_, _, let errorData):
                XCTAssertEqual(errorData, .array([.string("timeout"), .int(30)]))
                XCTAssertEqual(
                    error.localizedDescription,
                    "Command failed (setup_hook_failed): setup hook failed [error_data=[timeout, 30]]"
                )
            default:
                XCTFail("Unexpected RemoteCommandError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateSessionErrorWithUnknownObjectErrorDataRendersFallback() async {
        let transport = ErrorResponseRemoteTransport(
            response: RemoteCommandResponse(
                schemaVersion: 1,
                requestId: "req-error-object",
                type: "session.create.v1",
                status: "error",
                result: nil,
                errorCode: "setup_hook_failed",
                errorMessage: "setup hook failed",
                errorData: .object([
                    "reason": .string("quota"),
                    "retry_after_sec": .int(30)
                ]),
                createdAtMs: 1
            )
        )
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        do {
            _ = try await service.createSession(
                targetDeviceId: "22222222-2222-2222-2222-222222222222",
                repositoryId: "33333333-3333-3333-3333-333333333333",
                isWorktree: true
            )
            XCTFail("Expected commandFailed error")
        } catch let error as RemoteCommandError {
            switch error {
            case .commandFailed(_, _, let errorData):
                XCTAssertEqual(
                    errorData,
                    .object([
                        "reason": .string("quota"),
                        "retry_after_sec": .int(30)
                    ])
                )
                XCTAssertEqual(
                    error.localizedDescription,
                    "Command failed (setup_hook_failed): setup hook failed [error_data={reason=quota, retry_after_sec=30}]"
                )
            default:
                XCTFail("Unexpected RemoteCommandError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class RemoteCommandGitPayloadTests: XCTestCase {
    func testCommitChangesSendsPayloadAndParsesResult() async throws {
        let transport = CapturingResponseRemoteTransport(
            response: RemoteCommandResponse(
                schemaVersion: 1,
                requestId: "req-commit",
                type: "git.commit.v1",
                status: "ok",
                result: .object([
                    "oid": .string("abc123"),
                    "short_oid": .string("abc123"),
                    "summary": .string("Commit summary"),
                ]),
                errorCode: nil,
                errorMessage: nil,
                createdAtMs: 1
            )
        )
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        let result = try await service.commitChanges(
            targetDeviceId: "22222222-2222-2222-2222-222222222222",
            sessionId: "session-1",
            message: "Commit summary",
            authorName: "Test",
            authorEmail: "test@example.com",
            stageAll: true
        )

        XCTAssertEqual(result.oid, "abc123")
        XCTAssertEqual(result.shortOid, "abc123")
        XCTAssertEqual(result.summary, "Commit summary")

        let params = transport.publishedEnvelopes.last?.params
        XCTAssertEqual(params?["session_id"], .string("session-1"))
        XCTAssertEqual(params?["message"], .string("Commit summary"))
        XCTAssertEqual(params?["author_name"], .string("Test"))
        XCTAssertEqual(params?["author_email"], .string("test@example.com"))
        XCTAssertEqual(params?["stage_all"], .bool(true))
    }

    func testCommitChangesErrorMapsToCommandFailed() async {
        let transport = ErrorResponseRemoteTransport(
            response: RemoteCommandResponse(
                schemaVersion: 1,
                requestId: "req-error",
                type: "git.commit.v1",
                status: "error",
                result: nil,
                errorCode: "command_failed",
                errorMessage: "commit failed",
                errorData: .object([
                    "stderr": .string("nothing to commit"),
                ]),
                createdAtMs: 1
            )
        )
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        do {
            _ = try await service.commitChanges(
                targetDeviceId: "22222222-2222-2222-2222-222222222222",
                sessionId: "session-1",
                message: "Commit summary"
            )
            XCTFail("Expected commandFailed error")
        } catch let error as RemoteCommandError {
            switch error {
            case .commandFailed(let errorCode, let errorMessage, let errorData):
                XCTAssertEqual(errorCode, "command_failed")
                XCTAssertEqual(errorMessage, "commit failed")
                XCTAssertEqual(errorData?.objectValue?["stderr"], .string("nothing to commit"))
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPushChangesSendsPayloadAndParsesResult() async throws {
        let transport = CapturingResponseRemoteTransport(
            response: RemoteCommandResponse(
                schemaVersion: 1,
                requestId: "req-push",
                type: "git.push.v1",
                status: "ok",
                result: .object([
                    "remote": .string("origin"),
                    "branch": .string("main"),
                    "success": .bool(true),
                ]),
                errorCode: nil,
                errorMessage: nil,
                createdAtMs: 1
            )
        )
        let service = RemoteCommandService(
            transport: transport,
            authContextResolver: {
                (
                    userId: "test-user-id",
                    deviceId: "11111111-1111-1111-1111-111111111111"
                )
            },
            targetAvailabilityResolver: { _ in .online }
        )

        let result = try await service.pushChanges(
            targetDeviceId: "22222222-2222-2222-2222-222222222222",
            sessionId: "session-1",
            remote: "origin",
            branch: "main"
        )

        XCTAssertEqual(result.remote, "origin")
        XCTAssertEqual(result.branch, "main")
        XCTAssertTrue(result.success)

        let params = transport.publishedEnvelopes.last?.params
        XCTAssertEqual(params?["session_id"], .string("session-1"))
        XCTAssertEqual(params?["remote"], .string("origin"))
        XCTAssertEqual(params?["branch"], .string("main"))
    }
}

private final class NoopRemoteTransport: RemoteCommandTransport {
    func publishRemoteCommand(
        channel _: String,
        payload _: UMSecretRequestCommandPayload
    ) async throws {}

    func waitForAck(
        channel _: String,
        requestId _: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandAckEnvelope {
        RemoteCommandAckEnvelope(
            schemaVersion: 1,
            commandId: "noop",
            status: "accepted",
            createdAtMs: 1,
            resultB64: nil
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
            requestId: "noop",
            sessionId: "noop",
            senderDeviceId: "noop",
            receiverDeviceId: "noop",
            status: "error",
            errorCode: nil,
            ciphertextB64: nil,
            encapsulationPubkeyB64: nil,
            nonceB64: nil,
            algorithm: "noop",
            createdAtMs: 1
        )
    }

    func publishGenericCommand(
        channel _: String,
        envelope _: RemoteCommandEnvelope
    ) async throws {}

    func waitForCommandResponse(
        channel _: String,
        requestId _: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandResponse {
        RemoteCommandResponse(
            schemaVersion: 1,
            requestId: "noop",
            type: "noop",
            status: "ok",
            result: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAtMs: 1
        )
    }
}

private final class CapturingRemoteTransport: RemoteCommandTransport {
    var publishedEnvelopes: [RemoteCommandEnvelope] = []

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
            commandId: "noop",
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
            requestId: "noop",
            sessionId: "noop",
            senderDeviceId: "noop",
            receiverDeviceId: "noop",
            status: "error",
            errorCode: nil,
            ciphertextB64: nil,
            encapsulationPubkeyB64: nil,
            nonceB64: nil,
            algorithm: "noop",
            createdAtMs: 1
        )
    }

    func publishGenericCommand(
        channel _: String,
        envelope: RemoteCommandEnvelope
    ) async throws {
        publishedEnvelopes.append(envelope)
    }

    func waitForCommandResponse(
        channel _: String,
        requestId: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandResponse {
        RemoteCommandResponse(
            schemaVersion: 1,
            requestId: requestId,
            type: "session.create.v1",
            status: "ok",
            result: .object([
                "id": .string("session-1"),
                "repository_id": .string("repo-1"),
                "title": .string("Session"),
                "status": .string("active"),
                "is_worktree": publishedEnvelopes.last?.params["is_worktree"] ?? .bool(false),
                "worktree_path": .null,
                "created_at": .string("2026-01-01T00:00:00Z"),
            ]),
            errorCode: nil,
            errorMessage: nil,
            createdAtMs: 1
        )
    }
}

private final class ErrorResponseRemoteTransport: RemoteCommandTransport {
    private let response: RemoteCommandResponse

    init(response: RemoteCommandResponse) {
        self.response = response
    }

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
            commandId: "noop",
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
            requestId: "noop",
            sessionId: "noop",
            senderDeviceId: "noop",
            receiverDeviceId: "noop",
            status: "error",
            errorCode: nil,
            ciphertextB64: nil,
            encapsulationPubkeyB64: nil,
            nonceB64: nil,
            algorithm: "noop",
            createdAtMs: 1
        )
    }

    func publishGenericCommand(
        channel _: String,
        envelope _: RemoteCommandEnvelope
    ) async throws {}

    func waitForCommandResponse(
        channel _: String,
        requestId _: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandResponse {
        response
    }
}

private final class CapturingResponseRemoteTransport: RemoteCommandTransport {
    var publishedEnvelopes: [RemoteCommandEnvelope] = []
    private let response: RemoteCommandResponse

    init(response: RemoteCommandResponse) {
        self.response = response
    }

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
            commandId: "noop",
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
            requestId: "noop",
            sessionId: "noop",
            senderDeviceId: "noop",
            receiverDeviceId: "noop",
            status: "error",
            errorCode: nil,
            ciphertextB64: nil,
            encapsulationPubkeyB64: nil,
            nonceB64: nil,
            algorithm: "noop",
            createdAtMs: 1
        )
    }

    func publishGenericCommand(
        channel _: String,
        envelope: RemoteCommandEnvelope
    ) async throws {
        publishedEnvelopes.append(envelope)
    }

    func waitForCommandResponse(
        channel _: String,
        requestId: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandResponse {
        RemoteCommandResponse(
            schemaVersion: response.schemaVersion,
            requestId: requestId,
            type: response.type,
            status: response.status,
            result: response.result,
            errorCode: response.errorCode,
            errorMessage: response.errorMessage,
            errorData: response.errorData,
            createdAtMs: response.createdAtMs
        )
    }
}
