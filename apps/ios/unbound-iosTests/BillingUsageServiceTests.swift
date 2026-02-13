import XCTest

@testable import unbound_ios

final class BillingUsageCardStateTests: XCTestCase {
    func testCardStateFromStatusMapsOkToActive() {
        let status = makeStatus(enforcement: .ok)
        XCTAssertEqual(BillingUsageCardState.from(status: status), .active(status))
    }

    func testCardStateFromStatusMapsNearLimit() {
        let status = makeStatus(enforcement: .nearLimit)
        XCTAssertEqual(BillingUsageCardState.from(status: status), .nearLimit(status))
    }

    func testCardStateFromStatusMapsOverQuota() {
        let status = makeStatus(enforcement: .overQuota)
        XCTAssertEqual(BillingUsageCardState.from(status: status), .overLimit(status))
    }

    private func makeStatus(
        plan: BillingUsageStatus.Plan = .free,
        enforcement: BillingUsageStatus.EnforcementState
    ) -> BillingUsageStatus {
        BillingUsageStatus(
            plan: plan,
            gateway: "stripe",
            periodStart: "2026-02-01T00:00:00Z",
            periodEnd: "2026-03-01T00:00:00Z",
            commandsLimit: 50,
            commandsUsed: 49,
            commandsRemaining: 1,
            enforcementState: enforcement,
            updatedAt: "2026-02-13T10:00:00Z"
        )
    }
}
