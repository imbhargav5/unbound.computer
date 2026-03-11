import XCTest

@testable import unbound_macos

final class IconTooltipSpecTests: XCTestCase {
    func testLabelOnlyTooltipUsesLabelForDisplayAndHelp() {
        let spec = IconTooltipSpec("Close tab")

        XCTAssertEqual(spec.displayText, "Close tab")
        XCTAssertEqual(spec.helpText, "Close tab")
    }

    func testShortcutTooltipAppendsShortcutToDisplayAndHelp() {
        let spec = IconTooltipSpec("Settings", shortcut: "⌘,")

        XCTAssertEqual(spec.displayText, "Settings ⌘,")
        XCTAssertEqual(spec.helpText, "Settings ⌘,")
    }

    func testDefaultPlacementIsTop() {
        let spec = IconTooltipSpec("More actions")

        XCTAssertEqual(spec.placement, .top)
    }
}
