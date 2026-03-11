import XCTest

@testable import unbound_macos

#if DEBUG
final class GitViewModelSidebarRefreshPolicyTests: XCTestCase {
    @MainActor
    func testChangesTabRefreshesStatusOnly() {
        let viewModel = GitViewModel()

        XCTAssertEqual(viewModel.sidebarRefreshComponents(for: .changes), [.status])
    }

    @MainActor
    func testFilesTabRefreshesStatusOnly() {
        let viewModel = GitViewModel()

        XCTAssertEqual(viewModel.sidebarRefreshComponents(for: .files), [.status])
    }

    @MainActor
    func testCommitsTabRefreshesStatusBranchesAndCommits() {
        let viewModel = GitViewModel()

        XCTAssertEqual(
            viewModel.sidebarRefreshComponents(for: .commits),
            [.status, .branches, .commits]
        )
    }

    @MainActor
    func testUnsupportedTabsDoNotRefreshSidebarData() {
        let viewModel = GitViewModel()

        XCTAssertEqual(viewModel.sidebarRefreshComponents(for: .pullRequests), [])
        XCTAssertEqual(viewModel.sidebarRefreshComponents(for: .spec), [])
    }
}
#endif
