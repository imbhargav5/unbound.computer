import XCTest

@testable import unbound_macos

final class GitAgentPromptFactoryTests: XCTestCase {
    func testCommitPromptIncludesStageAndCommitInstructions() {
        let prompt = GitAgentPromptFactory.prompt(for: .commit).lowercased()

        XCTAssertTrue(prompt.contains("git add -a"))
        XCTAssertTrue(prompt.contains("commit"))
    }

    func testPushPromptIncludesPushInstruction() {
        let prompt = GitAgentPromptFactory.prompt(for: .push).lowercased()

        XCTAssertTrue(prompt.contains("push"))
        XCTAssertTrue(prompt.contains("upstream"))
    }

    func testRebaseAndPushPromptIncludesRebaseInstruction() {
        let prompt = GitAgentPromptFactory.prompt(for: .rebaseAndPush).lowercased()

        XCTAssertTrue(prompt.contains("rebase"))
        XCTAssertTrue(prompt.contains("push"))
    }

    func testCreatePullRequestPromptIncludesPrInstruction() {
        let prompt = GitAgentPromptFactory.prompt(for: .createPullRequest).lowercased()

        XCTAssertTrue(prompt.contains("pull request"))
        XCTAssertTrue(prompt.contains("url"))
    }

    func testCombinedPromptsPreserveRequiredOperations() {
        let commitPush = GitAgentPromptFactory.prompt(for: .commitAndPush).lowercased()
        let commitRebasePush = GitAgentPromptFactory.prompt(for: .commitRebaseAndPush).lowercased()
        let commitPr = GitAgentPromptFactory.prompt(for: .commitAndCreatePullRequest).lowercased()

        XCTAssertTrue(commitPush.contains("git add -a"))
        XCTAssertTrue(commitPush.contains("push"))
        XCTAssertTrue(commitRebasePush.contains("rebase"))
        XCTAssertTrue(commitPr.contains("pull request"))
    }
}
