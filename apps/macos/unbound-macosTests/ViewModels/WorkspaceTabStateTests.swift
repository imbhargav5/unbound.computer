import XCTest

@testable import unbound_macos

final class WorkspaceTabStateTests: XCTestCase {
    @MainActor
    func testResetForNewSessionClearsTerminalTabsAndSelectsConversation() {
        let state = WorkspaceTabState()
        let firstSessionId = UUID()
        let secondSessionId = UUID()

        _ = state.createTerminalTab(for: firstSessionId, workspacePath: "/tmp/first")
        XCTAssertEqual(state.terminalTabs.count, 1)

        state.resetForSession(secondSessionId, workspacePath: "/tmp/second")

        XCTAssertTrue(state.terminalTabs.isEmpty)
        XCTAssertEqual(state.selection, .conversation)
    }

    @MainActor
    func testCreateTerminalTabActivatesTabsSequentially() {
        let state = WorkspaceTabState()
        let sessionId = UUID()

        let firstTab = state.createTerminalTab(for: sessionId, workspacePath: "/tmp/repo")
        let secondTab = state.createTerminalTab(for: sessionId, workspacePath: "/tmp/repo")

        XCTAssertEqual(firstTab?.title, "Terminal 1")
        XCTAssertEqual(secondTab?.title, "Terminal 2")
        XCTAssertEqual(state.terminalTabs.count, 2)
        XCTAssertEqual(state.selection, .terminal(secondTab?.id ?? UUID()))
    }

    @MainActor
    func testResetForSameSessionWithoutWorkspacePathClearsTerminalTabs() {
        let state = WorkspaceTabState()
        let sessionId = UUID()

        _ = state.createTerminalTab(for: sessionId, workspacePath: "/tmp/repo")
        XCTAssertEqual(state.terminalTabs.count, 1)

        state.resetForSession(sessionId, workspacePath: nil)

        XCTAssertTrue(state.terminalTabs.isEmpty)
        XCTAssertEqual(state.selection, .conversation)
    }

    @MainActor
    func testCloseActiveTerminalFallsBackToNextTabOnRight() {
        let state = WorkspaceTabState()
        let sessionId = UUID()
        let firstTerminal = state.createTerminalTab(for: sessionId, workspacePath: "/tmp/repo")
        let secondTerminal = state.createTerminalTab(for: sessionId, workspacePath: "/tmp/repo")
        let editorId = UUID()

        state.selectTerminal(firstTerminal?.id ?? UUID())
        state.closeTerminalTab(firstTerminal?.id ?? UUID(), editorTabIds: [editorId])
        XCTAssertEqual(state.selection, .terminal(secondTerminal?.id ?? UUID()))

        state.selectTerminal(secondTerminal?.id ?? UUID())
        state.closeTerminalTab(secondTerminal?.id ?? UUID(), editorTabIds: [editorId])
        XCTAssertEqual(state.selection, .editor(editorId))
    }

    @MainActor
    func testClosingLastTerminalLeavesZeroTerminalTabs() {
        let state = WorkspaceTabState()
        let sessionId = UUID()
        let terminal = state.createTerminalTab(for: sessionId, workspacePath: "/tmp/repo")

        state.closeTerminalTab(terminal?.id ?? UUID(), editorTabIds: [])

        XCTAssertTrue(state.terminalTabs.isEmpty)
        XCTAssertEqual(state.selection, .conversation)
    }

    @MainActor
    func testCreateTerminalTabWithoutWorkspacePathIsNoOp() {
        let state = WorkspaceTabState()
        let created = state.createTerminalTab(for: UUID(), workspacePath: nil)

        XCTAssertNil(created)
        XCTAssertTrue(state.terminalTabs.isEmpty)
        XCTAssertEqual(state.selection, .conversation)
    }

    @MainActor
    func testSidebarCreationFlowSelectsRequestedSessionAndActivatesTerminalTab() {
        let repositoryId = UUID()
        let selectedSession = Session(id: UUID(), repositoryId: repositoryId, title: "Selected")
        let targetSession = Session(id: UUID(), repositoryId: repositoryId, title: "Target")
        let appState = AppState()
        let workspaceTabState = WorkspaceTabState()

        appState.configureForPreview(
            repositories: [Repository(id: repositoryId, path: "/tmp/repo")],
            sessions: [repositoryId: [selectedSession, targetSession]],
            selectedRepositoryId: repositoryId,
            selectedSessionId: selectedSession.id
        )

        appState.selectSession(targetSession.id)
        let created = workspaceTabState.createTerminalTab(
            for: targetSession.id,
            workspacePath: "/tmp/repo"
        )

        XCTAssertEqual(appState.selectedSessionId, targetSession.id)
        XCTAssertEqual(workspaceTabState.selection, .terminal(created?.id ?? UUID()))
        XCTAssertEqual(workspaceTabState.terminalTabs.count, 1)
    }
}
