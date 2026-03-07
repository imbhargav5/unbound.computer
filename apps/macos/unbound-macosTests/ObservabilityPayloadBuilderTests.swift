import CryptoKit
import Foundation
import Logging
import XCTest

@testable import unbound_macos

final class ObservabilityPayloadBuilderTests: XCTestCase {
    func testProdModeStripsRawMessageAndFields() {
        let builder = makeBuilder(mode: .prodMetadataOnly)
        let metadata: Logger.Metadata = [
            "request_id": "req_123",
            "session_id": "session_123",
            "access_token": "very-secret-token",
            "device_id": "device-123",
            "user_id": "user-456"
        ]

        let record = builder.build(
            level: .error,
            label: "app.auth",
            message: "token refresh failed",
            metadata: metadata
        )

        // Body should be event_code in prod mode, not raw message
        XCTAssertEqual(record.body, "macos.app.auth")
        // Sensitive fields should not appear in attributes
        XCTAssertNil(record.attributes["access_token"])
        // message_hash should be present
        XCTAssertNotNil(record.attributes["message_hash"])
        // device_id and user_id should be hashed
        XCTAssertNotNil(record.attributes["device_id_hash"])
        XCTAssertNotNil(record.attributes["user_id_hash"])
        // Severity should map correctly
        XCTAssertEqual(record.severityNumber, 17)
        XCTAssertEqual(record.severityText, "ERROR")
    }

    func testDevModeRedactsSensitiveMetadataValues() {
        let builder = makeBuilder(mode: .devVerbose)
        let metadata: Logger.Metadata = [
            "access_token": "very-secret-token",
            "authorization": "Bearer abc123",
            "safe_key": "safe-value"
        ]

        let record = builder.build(
            level: .info,
            label: "app.sync",
            message: "sync complete",
            metadata: metadata
        )

        XCTAssertEqual(record.attributes["fields.access_token"], "[REDACTED]")
        XCTAssertEqual(record.attributes["fields.authorization"], "[REDACTED]")
        XCTAssertEqual(record.attributes["fields.safe_key"], "safe-value")
    }

    func testSamplingIsDeterministicForEquivalentInput() {
        let builder = ObservabilityPayloadBuilder(
            config: ObservabilityRuntimeConfig(
                runtime: "macos",
                service: "macos",
                environment: "production",
                mode: .prodMetadataOnly,
                infoSampleRate: 0.5,
                debugSampleRate: 0.1,
                appVersion: "1.0.0",
                buildVersion: "42",
                osVersion: "macOS 15.7"
            )
        )

        let first = builder.shouldSample(
            level: .info,
            label: "app.state",
            message: "hello-observability"
        )
        let second = builder.shouldSample(
            level: .info,
            label: "app.state",
            message: "hello-observability"
        )

        XCTAssertEqual(first, second)
    }

    func testCorrelationAliasesAreCanonicalizedAndTagged() {
        let builder = makeBuilder(mode: .prodMetadataOnly)
        let metadata: Logger.Metadata = [
            "requestId": "req_alias",
            "sessionId": "session_alias",
            "traceId": "trace_alias",
            "spanId": "span_alias",
            "deviceId": "device_raw",
            "user_id_hash": "sha256:user_prehashed"
        ]

        let record = builder.build(
            level: .error,
            label: "app.sync",
            message: "sync failed",
            metadata: metadata
        )

        XCTAssertEqual(record.attributes["request_id"], "req_alias")
        XCTAssertEqual(record.attributes["session_id"], "session_alias")
        XCTAssertEqual(record.attributes["device_id_hash"], sha256("device_raw"))
        XCTAssertEqual(record.attributes["user_id_hash"], "sha256:user_prehashed")
        XCTAssertEqual(record.traceId, "trace_alias")
        XCTAssertEqual(record.spanId, "span_alias")
    }

    private func makeBuilder(mode: ObservabilityMode) -> ObservabilityPayloadBuilder {
        ObservabilityPayloadBuilder(
            config: ObservabilityRuntimeConfig(
                runtime: "macos",
                service: "macos",
                environment: mode == .prodMetadataOnly ? "production" : "development",
                mode: mode,
                infoSampleRate: 1.0,
                debugSampleRate: 1.0,
                appVersion: "1.0.0",
                buildVersion: "42",
                osVersion: "macOS 15.7"
            )
        )
    }

    private func sha256(_ rawValue: String) -> String {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}
