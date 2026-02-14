import XCTest

@testable import unbound_ios

final class ConfigTests: XCTestCase {
    func testDaemonPresenceChannelNormalizesUserIDToLowercase() {
        let channel = Config.daemonPresenceChannel(userId: "ABCDEF12-3456-7890-ABCD-EF1234567890")
        XCTAssertEqual(channel, "presence:abcdef12-3456-7890-abcd-ef1234567890")
    }
}
