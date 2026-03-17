import XCTest
@testable import unbound_macos

final class IssuesListFilterTests: XCTestCase {
    func testNewTabIncludesOnlyIssuesCreatedWithinLastSevenDays() {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let issues = [
            makeIssue(id: "recent", createdAt: isoDateString(offsetFrom: now, days: -2)),
            makeIssue(id: "older", createdAt: isoDateString(offsetFrom: now, days: -9)),
        ]

        let visible = issuesVisible(in: issues, tab: .new, now: now, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(visible.map(\.id), ["recent"])
    }

    func testAllTabIncludesAllNonHiddenIssues() {
        let issues = [
            makeIssue(id: "visible-1", createdAt: "2026-03-14T00:00:00Z"),
            makeIssue(id: "hidden", createdAt: "2026-03-13T00:00:00Z", hiddenAt: "2026-03-15T00:00:00Z"),
            makeIssue(id: "visible-2", createdAt: "2026-03-12T00:00:00Z"),
        ]

        let visible = issuesVisible(in: issues, tab: .all)

        XCTAssertEqual(visible.map(\.id), ["visible-1", "visible-2"])
    }

    func testNewTabKeepsExactSevenDayBoundaryInclusive() {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let threshold = calendar.date(byAdding: .day, value: -7, to: now)!
        let issues = [
            makeIssue(id: "boundary", createdAt: ISO8601DateFormatter().string(from: threshold)),
            makeIssue(id: "just-outside", createdAt: ISO8601DateFormatter().string(from: threshold.addingTimeInterval(-1))),
        ]

        let visible = issuesVisible(in: issues, tab: .new, now: now, calendar: calendar)

        XCTAssertEqual(visible.map(\.id), ["boundary"])
    }

    private func makeIssue(id: String, createdAt: String, hiddenAt: String? = nil) -> DaemonIssue {
        DaemonIssue(
            id: id,
            companyId: "company-1",
            projectId: nil,
            goalId: nil,
            parentId: nil,
            title: "Issue \(id)",
            description: nil,
            status: "backlog",
            priority: "medium",
            assigneeAgentId: nil,
            assigneeUserId: nil,
            checkoutRunId: nil,
            executionRunId: nil,
            executionAgentNameKey: nil,
            executionLockedAt: nil,
            createdByAgentId: nil,
            createdByUserId: nil,
            issueNumber: nil,
            identifier: nil,
            requestDepth: 0,
            billingCode: nil,
            assigneeAdapterOverrides: nil,
            executionWorkspaceSettings: nil,
            startedAt: nil,
            completedAt: nil,
            cancelledAt: nil,
            hiddenAt: hiddenAt,
            workspaceSessionId: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func isoDateString(offsetFrom date: Date, days: Int) -> String {
        let shifted = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date)!
        return ISO8601DateFormatter().string(from: shifted)
    }
}
