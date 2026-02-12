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
