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
        XCTAssertEqual(event.sentryMessage, "macos.app.auth")
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
}
