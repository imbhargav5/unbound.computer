import Foundation
import XCTest

@testable import unbound_macos

final class ObservabilityTransportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testSinkNormalizesEndpointAndSendsOTLPLogsPayload() throws {
        let requestExpectation = expectation(description: "OTLP request")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:4318/v1/logs")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")

            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let resourceLogs = try XCTUnwrap(json["resourceLogs"] as? [[String: Any]])
            let firstResourceLog = try XCTUnwrap(resourceLogs.first)
            let resource = try XCTUnwrap(firstResourceLog["resource"] as? [String: Any])
            let resourceAttributes = try XCTUnwrap(resource["attributes"] as? [[String: Any]])
            let scopeLogs = try XCTUnwrap(firstResourceLog["scopeLogs"] as? [[String: Any]])
            let firstScopeLog = try XCTUnwrap(scopeLogs.first)
            let logRecords = try XCTUnwrap(firstScopeLog["logRecords"] as? [[String: Any]])
            let firstLogRecord = try XCTUnwrap(logRecords.first)

            XCTAssertEqual(
                Self.stringValue(for: "service.name", in: resourceAttributes),
                "macos"
            )
            XCTAssertEqual(
                Self.stringValue(for: "deployment.environment", in: resourceAttributes),
                "development"
            )
            XCTAssertEqual(firstLogRecord["severityText"] as? String, "INFO")

            requestExpectation.fulfill()
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let sink = try XCTUnwrap(
            makeSink(
                endpoint: URL(string: "http://localhost:4318"),
                headers: ["Authorization": "Bearer token"]
            )
        )

        sink.export(makeRecord())
        XCTAssertTrue(sink.flush(timeout: 1.0))
        wait(for: [requestExpectation], timeout: 1.0)
    }

    func testNon2xxResponsesEmitRateLimitedLocalDiagnostics() throws {
        var diagnostics: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data("collector unavailable".utf8)
            )
        }

        let sink = try XCTUnwrap(
            makeSink(
                endpoint: URL(string: "http://localhost:4318"),
                diagnosticHandler: { diagnostics.append($0) },
                currentDate: { now },
                diagnosticMinimumInterval: 60.0
            )
        )

        sink.export(makeRecord())
        XCTAssertTrue(sink.flush(timeout: 1.0))

        sink.export(makeRecord())
        XCTAssertTrue(sink.flush(timeout: 1.0))

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertTrue(diagnostics[0].contains("HTTP 503"))
        XCTAssertTrue(diagnostics[0].contains("collector unavailable"))
    }

    func testTransportErrorsEmitLocalDiagnostics() throws {
        var diagnostics: [String] = []

        MockURLProtocol.requestHandler = { _ in
            throw NSError(
                domain: "ObservabilityTransportTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "connection refused"]
            )
        }

        let sink = try XCTUnwrap(
            makeSink(
                endpoint: URL(string: "http://localhost:4318"),
                diagnosticHandler: { diagnostics.append($0) }
            )
        )

        sink.export(makeRecord())
        XCTAssertTrue(sink.flush(timeout: 1.0))

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertTrue(diagnostics[0].contains("connection refused"))
    }

    private func makeSink(
        endpoint: URL?,
        headers: [String: String] = [:],
        diagnosticHandler: @escaping (String) -> Void = { _ in },
        currentDate: @escaping () -> Date = Date.init,
        diagnosticMinimumInterval: TimeInterval = 30.0
    ) -> ObservabilityOTLPSink? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        return ObservabilityOTLPSink(
            endpoint: endpoint,
            headers: headers,
            config: ObservabilityRuntimeConfig(
                runtime: "macos",
                service: "macos",
                environment: "development",
                mode: .devVerbose,
                infoSampleRate: 1.0,
                debugSampleRate: 1.0,
                appVersion: "1.0.0",
                buildVersion: "42",
                osVersion: "macOS 15.7"
            ),
            session: session,
            diagnosticHandler: diagnosticHandler,
            currentDate: currentDate,
            diagnosticMinimumInterval: diagnosticMinimumInterval
        )
    }

    private func makeRecord() -> OTLPLogRecord {
        OTLPLogRecord(
            timeUnixNano: 1,
            severityNumber: 9,
            severityText: "INFO",
            body: "startup",
            scopeName: "app.observability",
            attributes: [
                "event_code": "macos.observability.startup",
                "component": "observability"
            ],
            traceId: nil,
            spanId: nil
        )
    }

    private static func stringValue(
        for key: String,
        in attributes: [[String: Any]]
    ) -> String? {
        guard let attribute = attributes.first(where: { $0["key"] as? String == key }),
              let value = attribute["value"] as? [String: Any]
        else {
            return nil
        }

        return value["stringValue"] as? String
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("Missing MockURLProtocol.requestHandler")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
