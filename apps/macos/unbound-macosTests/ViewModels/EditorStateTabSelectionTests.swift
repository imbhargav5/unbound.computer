import XCTest

@testable import unbound_macos

final class EditorStateTabSelectionTests: XCTestCase {
    @MainActor
    func testOpenFileTabReturnsNewTabIDAndSelectsIt() {
        let state = EditorState()

        let openedTabId = state.openFileTab(
            relativePath: "Sources/App.swift",
            fullPath: "/tmp/repo/Sources/App.swift",
            sessionId: UUID()
        )

        XCTAssertEqual(state.selectedTabId, openedTabId)
        XCTAssertEqual(state.tabs.map(\.id), [openedTabId])
    }

    @MainActor
    func testOpenFileTabReturnsExistingTabIDForDuplicatePath() {
        let state = EditorState()
        let firstTabId = state.openFileTab(
            relativePath: "Sources/App.swift",
            fullPath: "/tmp/repo/Sources/App.swift",
            sessionId: UUID()
        )

        let reopenedTabId = state.openFileTab(
            relativePath: "Sources/App.swift",
            fullPath: "/tmp/repo/Sources/App.swift",
            sessionId: UUID()
        )

        XCTAssertEqual(reopenedTabId, firstTabId)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.selectedTabId, firstTabId)
    }

    @MainActor
    func testOpenDiffTabReturnsExistingTabIDForDuplicatePath() {
        let state = EditorState()
        let firstTabId = state.openDiffTab(relativePath: "Sources/App.swift")

        let reopenedTabId = state.openDiffTab(relativePath: "Sources/App.swift")

        XCTAssertEqual(reopenedTabId, firstTabId)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.selectedTabId, firstTabId)
    }
}
