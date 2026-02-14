import XCTest

@testable import unbound_ios

final class DevicePresenceServiceTests: XCTestCase {
    func testDaemonPresenceUserIDMatchIsCaseInsensitive() {
        let expected = "ABCDEF12-3456-7890-ABCD-EF1234567890"
        let payload = "abcdef12-3456-7890-abcd-ef1234567890"

        XCTAssertTrue(DevicePresenceService.daemonPresenceUserIDsMatch(expected: expected, payload: payload))
    }
}
