import XCTest
@testable import unbound_macos

final class AppStateBoardShellTests: XCTestCase {
    @MainActor
    func testCurrentShellReturnsFirstCompanySetupWhenInitialLoadCompletesWithoutCompanies() {
        let appState = AppState()

        appState.configureForPreview(
            companies: [],
            hasCompletedInitialCompanyLoad: true
        )

        XCTAssertEqual(appState.currentShell, .firstCompanySetup)
    }

    @MainActor
    func testCurrentShellReturnsCeoSetupRequiredWhenSelectedCompanyHasNoCEO() {
        let appState = AppState()
        let company = makeCompany(id: "company-1", ceoAgentId: nil)

        appState.configureForPreview(
            companies: [company],
            selectedCompanyId: company.id,
            hasCompletedInitialCompanyLoad: true
        )

        XCTAssertEqual(appState.currentShell, .ceoSetupRequired)
    }

    @MainActor
    func testCurrentShellReturnsCompanyDashboardWhenSelectedCompanyHasCEO() {
        let appState = AppState()
        let company = makeCompany(id: "company-1", ceoAgentId: "agent-1")

        appState.configureForPreview(
            companies: [company],
            selectedCompanyId: company.id,
            hasCompletedInitialCompanyLoad: true,
            selectedScreen: .dashboard
        )

        XCTAssertEqual(appState.currentShell, .companyDashboard)
    }

    @MainActor
    func testCurrentShellStaysInCeoSetupWhenBootstrapIssueIsStillPending() {
        let appState = AppState()
        let company = makeCompany(id: "company-1", ceoAgentId: "agent-1")

        appState.configureForPreview(
            companies: [company],
            selectedCompanyId: company.id,
            hasCompletedInitialCompanyLoad: true,
            selectedScreen: .dashboard,
            boardOnboardingState: BoardOnboardingState(
                companyId: company.id,
                step: .bootstrapIssue,
                ceoName: "CEO",
                ceoTitle: "Chief Executive Officer",
                bootstrapIssueTitle: "Create your CEO HEARTBEAT.md",
                bootstrapIssueDescription: "Bootstrap the CEO.",
                ceoAgentId: "agent-1"
            )
        )

        XCTAssertEqual(appState.currentShell, .ceoSetupRequired)
    }

    @MainActor
    func testCurrentShellReturnsWorkspaceWhenSelectedCompanyHasCEOAndWorkspaceSelected() {
        let appState = AppState()
        let company = makeCompany(id: "company-1", ceoAgentId: "agent-1")

        appState.configureForPreview(
            companies: [company],
            selectedCompanyId: company.id,
            hasCompletedInitialCompanyLoad: true,
            selectedScreen: .workspaces
        )

        XCTAssertEqual(appState.currentShell, .workspace)
    }

    @MainActor
    func testShowIssuesListSelectsIssuesScreenAndListDestination() {
        let appState = AppState()

        appState.showIssuesList(tab: .all)

        XCTAssertEqual(appState.selectedScreen, .issues)
        XCTAssertEqual(appState.selectedIssuesListTab, .all)
        XCTAssertEqual(appState.issuesRouteDestination, .list)
    }

    @MainActor
    func testShowIssueDetailSelectsIssuesScreenAndDetailDestination() {
        let appState = AppState()

        appState.showIssueDetail(issueId: "issue-123")

        XCTAssertEqual(appState.selectedScreen, .issues)
        XCTAssertEqual(appState.selectedIssueId, "issue-123")
        XCTAssertEqual(appState.issuesRouteDestination, .detail(issueId: "issue-123"))
    }

    @MainActor
    func testReconcileIssuesRouteStateFallsBackToListWhenIssueIsMissing() {
        let appState = AppState()
        let company = makeCompany(id: "company-1", ceoAgentId: "agent-1")

        appState.configureForPreview(
            companies: [company],
            issues: [makeIssue(id: "issue-1", createdAt: "2026-03-14T00:00:00Z")],
            selectedCompanyId: company.id,
            selectedIssueId: "missing-issue",
            hasCompletedInitialCompanyLoad: true,
            selectedScreen: .issues,
            issuesRouteDestination: .detail(issueId: "missing-issue")
        )

        appState.reconcileIssuesRouteState()

        XCTAssertNil(appState.selectedIssueId)
        XCTAssertEqual(appState.issuesRouteDestination, .list)
    }

    func testDefaultBootstrapIssueDescriptionForbidsFilesystemBasedHiring() {
        let description = BoardOnboardingState.defaultBootstrapIssueDescription(companyName: "Acme")

        XCTAssertTrue(description.contains("board-native hire request"))
        XCTAssertTrue(description.contains("Do not create sibling agent directories"))
    }

    private func makeCompany(id: String, ceoAgentId: String?) -> DaemonCompany {
        DaemonCompany(
            id: id,
            name: "Acme",
            description: nil,
            status: "active",
            issuePrefix: "ACM",
            issueCounter: 0,
            budgetMonthlyCents: 0,
            spentMonthlyCents: 0,
            requireBoardApprovalForNewAgents: true,
            brandColor: nil,
            ceoAgentId: ceoAgentId,
            createdAt: "2026-03-14T00:00:00Z",
            updatedAt: "2026-03-14T00:00:00Z"
        )
    }

    private func makeIssue(
        id: String,
        createdAt: String,
        updatedAt: String? = nil,
        hiddenAt: String? = nil
    ) -> DaemonIssue {
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
            issueNumber: 1,
            identifier: "ACM-1",
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
            updatedAt: updatedAt ?? createdAt
        )
    }
}
