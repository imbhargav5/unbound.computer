import CryptoKit
import Foundation
import Logging
import XCTest

@testable import unbound_ios

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

        let event = builder.build(
            level: .error,
            label: "app.auth",
            message: "token refresh failed",
            metadata: metadata
        )

        XCTAssertNil(event.posthogProperties["message"])
        XCTAssertNil(event.posthogProperties["fields"])
        XCTAssertNil(event.posthogProperties["access_token"])
        XCTAssertNotNil(event.posthogProperties["message_hash"])
        XCTAssertNotNil(event.posthogProperties["device_id_hash"])
        XCTAssertNotNil(event.posthogProperties["user_id_hash"])
        XCTAssertEqual(event.sentryLevel, "error")
        XCTAssertEqual(event.sentryMessage, "ios.app.auth")
    }

    func testDevModeRedactsSensitiveMetadataValues() {
        let builder = makeBuilder(mode: .devVerbose)
        let metadata: Logger.Metadata = [
            "access_token": "very-secret-token",
            "authorization": "Bearer abc123",
            "safe_key": "safe-value"
        ]

        let event = builder.build(
            level: .info,
            label: "app.sync",
            message: "sync complete",
            metadata: metadata
        )

        let fields = event.posthogProperties["fields"] as? [String: Any]
        XCTAssertEqual(fields?["access_token"] as? String, "[REDACTED]")
        XCTAssertEqual(fields?["authorization"] as? String, "[REDACTED]")
        XCTAssertEqual(fields?["safe_key"] as? String, "safe-value")
    }

    func testSamplingIsDeterministicForEquivalentInput() {
        let builder = ObservabilityPayloadBuilder(
            config: ObservabilityRuntimeConfig(
                runtime: "ios",
                service: "ios",
                environment: "production",
                mode: .prodMetadataOnly,
                infoSampleRate: 0.5,
                debugSampleRate: 0.1,
                appVersion: "1.0.0",
                buildVersion: "42",
                osVersion: "iOS 18.2"
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

        let event = builder.build(
            level: .error,
            label: "app.sync",
            message: "sync failed",
            metadata: metadata
        )

        XCTAssertEqual(event.posthogProperties["request_id"] as? String, "req_alias")
        XCTAssertEqual(event.posthogProperties["session_id"] as? String, "session_alias")
        XCTAssertEqual(event.posthogProperties["trace_id"] as? String, "trace_alias")
        XCTAssertEqual(event.posthogProperties["span_id"] as? String, "span_alias")
        XCTAssertEqual(event.posthogProperties["device_id_hash"] as? String, sha256("device_raw"))
        XCTAssertEqual(event.posthogProperties["user_id_hash"] as? String, "sha256:user_prehashed")
        XCTAssertEqual(event.sentryTags["trace_id"], "trace_alias")
        XCTAssertEqual(event.sentryTags["span_id"], "span_alias")
    }

    private func makeBuilder(mode: ObservabilityMode) -> ObservabilityPayloadBuilder {
        ObservabilityPayloadBuilder(
            config: ObservabilityRuntimeConfig(
                runtime: "ios",
                service: "ios",
                environment: mode == .prodMetadataOnly ? "production" : "development",
                mode: mode,
                infoSampleRate: 1.0,
                debugSampleRate: 1.0,
                appVersion: "1.0.0",
                buildVersion: "42",
                osVersion: "iOS 18.2"
            )
        )
    }

    private func sha256(_ rawValue: String) -> String {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}
