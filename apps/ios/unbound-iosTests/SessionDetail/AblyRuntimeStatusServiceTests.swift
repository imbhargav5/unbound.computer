import Foundation
import XCTest

@testable import unbound_ios

final class AblyRuntimeStatusServiceTests: XCTestCase {
    func testDecodeFromLiveObjectMessageExtractsRuntimeEnvelopeFromValue() {
        let payload: [String: Any] = [
            "schema_version": 1,
            "coding_session": [
                "status": "running",
            ],
            "device_id": "11111111-1111-1111-1111-111111111111",
            "session_id": "22222222-2222-2222-2222-222222222222",
            "updated_at_ms": 1234,
        ]
        let message: [String: Any] = [
            "name": "coding_session_status",
            "op": "set",
            "value": payload,
        ]

        let envelope = SessionDetailRuntimeStatusEnvelope.decodeFromLiveObjectMessage(
            message,
            expectedObjectKey: "coding_session_status"
        )

        XCTAssertEqual(envelope?.schemaVersion, 1)
        XCTAssertEqual(envelope?.codingSession.status, .running)
        XCTAssertEqual(envelope?.normalizedDeviceId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(envelope?.normalizedSessionId, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(envelope?.updatedAtMs, 1234)
    }

    func testDecodeFromLiveObjectMessageIgnoresUnexpectedObjectName() {
        let message: [String: Any] = [
            "name": "some_other_object",
            "value": [
                "schema_version": 1,
                "coding_session": ["status": "idle"],
                "device_id": "11111111-1111-1111-1111-111111111111",
                "session_id": "22222222-2222-2222-2222-222222222222",
                "updated_at_ms": 1,
            ],
        ]

        let envelope = SessionDetailRuntimeStatusEnvelope.decodeFromLiveObjectMessage(
            message,
            expectedObjectKey: "coding_session_status"
        )

        XCTAssertNil(envelope)
    }

    func testRuntimeStatusUnknownValueFallsBackToNotAvailable() throws {
        let payload: [String: Any] = [
            "schema_version": 1,
            "coding_session": ["status": "totally-new"],
            "device_id": "11111111-1111-1111-1111-111111111111",
            "session_id": "22222222-2222-2222-2222-222222222222",
            "updated_at_ms": 10,
        ]

        let decoded = try XCTUnwrap(try SessionDetailRuntimeStatusEnvelope.decodeEnvelopePayload(payload))
        XCTAssertEqual(decoded.codingSession.status, .notAvailable)
    }

    func testNormalizedErrorMessageTrimsAndDropsEmptyValues() {
        let envelope = SessionDetailRuntimeStatusEnvelope(
            schemaVersion: 1,
            codingSession: SessionDetailRuntimeState(status: .error, errorMessage: "  daemon failed  "),
            deviceId: "11111111-1111-1111-1111-111111111111",
            sessionId: "22222222-2222-2222-2222-222222222222",
            updatedAtMs: 123
        )
        XCTAssertEqual(envelope.normalizedErrorMessage, "daemon failed")

        let empty = SessionDetailRuntimeStatusEnvelope(
            schemaVersion: 1,
            codingSession: SessionDetailRuntimeState(status: .error, errorMessage: "   "),
            deviceId: "11111111-1111-1111-1111-111111111111",
            sessionId: "22222222-2222-2222-2222-222222222222",
            updatedAtMs: 123
        )
        XCTAssertNil(empty.normalizedErrorMessage)
    }
}
