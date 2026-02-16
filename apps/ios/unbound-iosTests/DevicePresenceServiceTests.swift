import XCTest

@testable import unbound_ios

@MainActor
final class DevicePresenceServiceTests: XCTestCase {
    private let service = DevicePresenceService.shared
    private let deviceID = "8C0527A8-B0BC-42F6-BB55-EA5A94ACCB55"

    override func setUp() {
        super.setUp()
        service._testResetDaemonPresenceState()
    }

    override func tearDown() {
        service._testResetDaemonPresenceState()
        super.tearDown()
    }

    func testDaemonPresenceUserIDMatchIsCaseInsensitive() {
        let expected = "ABCDEF12-3456-7890-ABCD-EF1234567890"
        let payload = "abcdef12-3456-7890-abcd-ef1234567890"

        XCTAssertTrue(DevicePresenceService.daemonPresenceUserIDsMatch(expected: expected, payload: payload))
    }

    func testDaemonAvailabilityIsUnknownWithoutSignals() {
        XCTAssertEqual(service.daemonAvailability(id: deviceID), .unknown)
    }

    func testMergedStatusIsOfflineWithoutSignals() {
        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: nil), .offline)
    }

    func testMergedStatusUsesFreshSupabaseTimestamp() {
        let supabaseLastSeen = Date().addingTimeInterval(-5)
        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: supabaseLastSeen), .online)
    }

    func testMergedStatusMarksStaleSupabaseTimestampOffline() {
        let supabaseLastSeen = Date().addingTimeInterval(-20)
        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: supabaseLastSeen), .offline)
    }

    func testDaemonOnlineSignalSetsAvailabilityOnline() {
        service._testApplyDaemonPresence(deviceID: deviceID, status: "online", at: Date().addingTimeInterval(-2))
        XCTAssertEqual(service.daemonAvailability(id: deviceID), .online)
        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: nil), .online)
    }

    func testDaemonOnlineSignalExpiresToOfflineAfterTTL() {
        service._testApplyDaemonPresence(deviceID: deviceID, status: "online", at: Date().addingTimeInterval(-20))
        XCTAssertEqual(service.daemonAvailability(id: deviceID), .offline)
        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: nil), .offline)
    }

    func testMergedStatusPrefersNewestOfflineSignalOverOlderSupabaseOnline() {
        let olderSupabaseOnline = Date().addingTimeInterval(-9)
        let newerOffline = Date().addingTimeInterval(-1)
        service._testApplyDaemonPresence(deviceID: deviceID, status: "offline", at: newerOffline)

        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: olderSupabaseOnline), .offline)
    }

    func testMergedStatusPrefersNewerSupabaseOnlineOverOlderOfflineSignal() {
        let olderOffline = Date().addingTimeInterval(-20)
        let newerSupabaseOnline = Date().addingTimeInterval(-2)
        service._testApplyDaemonPresence(deviceID: deviceID, status: "offline", at: olderOffline)

        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: newerSupabaseOnline), .online)
    }

    func testOnlineSignalClearsPriorOfflineSignal() {
        service._testApplyDaemonPresence(deviceID: deviceID, status: "offline", at: Date().addingTimeInterval(-4))
        service._testApplyDaemonPresence(deviceID: deviceID, status: "online", at: Date().addingTimeInterval(-1))

        XCTAssertEqual(service.daemonAvailability(id: deviceID), .online)
        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: nil), .online)
    }

    func testOfflineSignalClearsPriorOnlineSignal() {
        service._testApplyDaemonPresence(deviceID: deviceID, status: "online", at: Date().addingTimeInterval(-2))
        service._testApplyDaemonPresence(deviceID: deviceID, status: "offline", at: Date())

        XCTAssertEqual(service.daemonAvailability(id: deviceID), .offline)
        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID, supabaseLastSeenAt: nil), .offline)
    }

    func testDeviceIDNormalizationHandlesCaseAndWhitespace() {
        service._testApplyDaemonPresence(
            deviceID: "  8c0527a8-b0bc-42f6-bb55-ea5a94accb55  ",
            status: "online",
            at: Date().addingTimeInterval(-1)
        )

        XCTAssertEqual(service.daemonAvailability(id: deviceID), .online)
        XCTAssertEqual(service.mergedDeviceStatus(id: deviceID.lowercased(), supabaseLastSeenAt: nil), .online)
    }

    func testDaemonStatusVersionIncrementsForRecognizedSignals() {
        XCTAssertEqual(service.daemonStatusVersion, 0)

        service._testApplyDaemonPresence(deviceID: deviceID, status: "online", at: Date())
        XCTAssertEqual(service.daemonStatusVersion, 1)

        service._testApplyDaemonPresence(deviceID: deviceID, status: "offline", at: Date())
        XCTAssertEqual(service.daemonStatusVersion, 2)

        service._testApplyDaemonPresence(deviceID: deviceID, status: "unknown", at: Date())
        XCTAssertEqual(service.daemonStatusVersion, 2)
    }
}
