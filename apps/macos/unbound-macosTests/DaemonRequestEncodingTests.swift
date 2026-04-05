import Foundation
import XCTest

@testable import unbound_macos

final class DaemonRequestEncodingTests: XCTestCase {
    func testAgentRunLogOffsetEncodesAsJSONNumber() throws {
        let request = DaemonRequest(
            method: .agentRunLog,
            params: [
                "run_id": "run-123",
                "offset": UInt64(0),
                "limit_bytes": 16_384,
            ]
        )

        let line = try request.toJsonLine()
        let data = try XCTUnwrap(line.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let params = try XCTUnwrap(object["params"] as? [String: Any])

        XCTAssertEqual(params["offset"] as? NSNumber, 0)
        XCTAssertFalse(params["offset"] is String)
    }
}
