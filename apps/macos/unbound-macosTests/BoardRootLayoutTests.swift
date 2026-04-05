import XCTest
@testable import unbound_macos

final class BoardRootLayoutTests: XCTestCase {
    func testSettingsScreenUsesDedicatedSettingsLayout() {
        let layout = boardRootLayout(
            currentShell: .companyDashboard,
            selectedScreen: .settings
        )

        XCTAssertEqual(layout, .settings)
    }

    func testDashboardScreensKeepCompanyDashboardLayout() {
        XCTAssertEqual(
            boardRootLayout(
                currentShell: .companyDashboard,
                selectedScreen: .dashboard
            ),
            .companyDashboard
        )

        XCTAssertEqual(
            boardRootLayout(
                currentShell: .companyDashboard,
                selectedScreen: .issues
            ),
            .companyDashboard
        )
    }

    func testWorkspaceShellTakesPriorityOverSettingsScreen() {
        let layout = boardRootLayout(
            currentShell: .workspace,
            selectedScreen: .settings
        )

        XCTAssertEqual(layout, .workspace)
    }
}
