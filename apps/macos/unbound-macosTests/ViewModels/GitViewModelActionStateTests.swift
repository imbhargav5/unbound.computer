import XCTest

@testable import unbound_macos

#if DEBUG
final class GitViewModelActionStateTests: XCTestCase {
    func testHasUncommittedChangesDetectsDirtyStatus() {
        let viewModel = GitViewModel()

        viewModel.configureForPreview(
            repositoryPath: "/tmp/repo",
            currentBranch: "main",
            status: GitStatusResult(
                files: [GitStatusFile(path: "README.md", status: .modified, staged: false)],
                branch: "main",
                isClean: false
            ),
            localBranches: [currentBranch(upstream: "origin/main", ahead: 0, behind: 0)]
        )

        XCTAssertTrue(viewModel.hasUncommittedChanges)
    }

    func testHasUnpushedCommitsRequiresUpstreamAndAhead() {
        let viewModel = GitViewModel()

        viewModel.configureForPreview(
            repositoryPath: "/tmp/repo",
            currentBranch: "main",
            status: GitStatusResult(files: [], branch: "main", isClean: true),
            localBranches: [currentBranch(upstream: "origin/main", ahead: 2, behind: 0)]
        )

        XCTAssertTrue(viewModel.hasUnpushedCommits)
        XCTAssertEqual(viewModel.aheadCount, 2)
        XCTAssertEqual(viewModel.behindCount, 0)
    }

    func testHasUnpushedCommitsFalseWithoutUpstream() {
        let viewModel = GitViewModel()

        viewModel.configureForPreview(
            repositoryPath: "/tmp/repo",
            currentBranch: "main",
            status: GitStatusResult(files: [], branch: "main", isClean: true),
            localBranches: [currentBranch(upstream: nil, ahead: 4, behind: 0)]
        )

        XCTAssertFalse(viewModel.hasUnpushedCommits)
    }

    func testHasUnpushedCommitsFalseWhenAheadIsZero() {
        let viewModel = GitViewModel()

        viewModel.configureForPreview(
            repositoryPath: "/tmp/repo",
            currentBranch: "main",
            status: GitStatusResult(files: [], branch: "main", isClean: true),
            localBranches: [currentBranch(upstream: "origin/main", ahead: 0, behind: 3)]
        )

        XCTAssertFalse(viewModel.hasUnpushedCommits)
        XCTAssertEqual(viewModel.behindCount, 3)
    }

    func testMixedStateInputsKeepBothFlagsTrue() {
        let viewModel = GitViewModel()

        viewModel.configureForPreview(
            repositoryPath: "/tmp/repo",
            currentBranch: "main",
            status: GitStatusResult(
                files: [GitStatusFile(path: "Sources/App.swift", status: .modified, staged: true)],
                branch: "main",
                isClean: false
            ),
            localBranches: [currentBranch(upstream: "origin/main", ahead: 1, behind: 0)]
        )

        XCTAssertTrue(viewModel.hasUncommittedChanges)
        XCTAssertTrue(viewModel.hasUnpushedCommits)
    }

    private func currentBranch(upstream: String?, ahead: UInt32, behind: UInt32) -> GitBranch {
        GitBranch(
            name: "main",
            isCurrent: true,
            isRemote: false,
            upstream: upstream,
            ahead: ahead,
            behind: behind,
            headOid: "abc123"
        )
    }
}
#endif
