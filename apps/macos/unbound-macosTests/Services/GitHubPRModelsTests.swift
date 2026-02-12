import XCTest

@testable import unbound_macos

final class GitHubPRModelsTests: XCTestCase {
    func testDaemonMethodIncludesGhMethods() {
        XCTAssertEqual(DaemonMethod.ghAuthStatus.rawValue, "gh.auth_status")
        XCTAssertEqual(DaemonMethod.ghPrCreate.rawValue, "gh.pr_create")
        XCTAssertEqual(DaemonMethod.ghPrView.rawValue, "gh.pr_view")
        XCTAssertEqual(DaemonMethod.ghPrList.rawValue, "gh.pr_list")
        XCTAssertEqual(DaemonMethod.ghPrChecks.rawValue, "gh.pr_checks")
        XCTAssertEqual(DaemonMethod.ghPrMerge.rawValue, "gh.pr_merge")
    }

    func testDecodesPullRequestListResponse() throws {
        let json = """
        {
          "pull_requests": [
            {
              "number": 42,
              "title": "Add bakugou GH integration",
              "url": "https://github.com/unbound/repo/pull/42",
              "state": "OPEN",
              "is_draft": false,
              "base_ref_name": "main",
              "head_ref_name": "feature/bakugou",
              "merge_state_status": "CLEAN",
              "labels": [{"name": "automation"}],
              "author": {"login": "bhargav"}
            }
          ],
          "count": 1
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GHPRListResponse.self, from: json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.pullRequests.count, 1)
        XCTAssertEqual(decoded.pullRequests.first?.number, 42)
        XCTAssertEqual(decoded.pullRequests.first?.labels.first?.name, "automation")
        XCTAssertEqual(decoded.pullRequests.first?.author?.login, "bhargav")
    }

    func testDecodesChecksSummaryResponse() throws {
        let json = """
        {
          "checks": [
            {
              "name": "CI",
              "state": "completed",
              "bucket": "pass",
              "workflow": "build",
              "started_at": "2026-02-12T10:00:00Z",
              "completed_at": "2026-02-12T10:05:00Z"
            }
          ],
          "summary": {
            "total": 1,
            "passing": 1,
            "failing": 0,
            "pending": 0,
            "skipped": 0,
            "cancelled": 0
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GHPRChecksResponse.self, from: json)
        XCTAssertEqual(decoded.summary.total, 1)
        XCTAssertEqual(decoded.summary.passing, 1)
        XCTAssertEqual(decoded.checks.first?.name, "CI")
        XCTAssertEqual(decoded.checks.first?.workflow, "build")
    }
}
