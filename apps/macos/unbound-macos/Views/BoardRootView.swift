//
//  BoardRootView.swift
//  unbound-macos
//
//  Native macOS shell for the Unbound local board.
//

import AppKit
import Logging
import SwiftUI

private let boardLogger = Logger(label: "app.ui.board")

struct BoardRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingCreateCompanySheet = false
    @State private var showingCreateIssueSheet = false
    @State private var showingCreateProjectDialog = false
    @State private var showingCreateAgentInfoDialog = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            CompanyRail(
                companies: appState.companies,
                selectedCompanyId: appState.selectedCompanyId,
                selectedScreen: appState.selectedScreen,
                onSelectCompany: { companyId in
                    Task { await appState.selectCompany(companyId) }
                },
                onGoToCompanyDashboard: { companyId in
                    Task {
                        await appState.selectCompany(companyId)
                        appState.selectedScreen = .dashboard
                    }
                },
                onCreateCompany: { showingCreateCompanySheet = true },
                onOpenSettings: { appState.selectedScreen = .settings }
            )

            if appState.currentShell == .workspace {
                BoardWorkspacesRoute()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CompanyDashboardSidebar(
                    selectedCompany: appState.selectedCompany,
                    agents: sidebarOrderedAgents(appState.agents, ceoAgentId: appState.selectedCompany?.ceoAgentId),
                    selectedScreen: appState.selectedScreen,
                    selectedAgentId: appState.selectedAgentId,
                    isLoading: appState.isLoadingBoardData,
                    boardError: appState.boardError,
                    onRefresh: {
                        Task {
                            await appState.refreshCompanies()
                            await appState.refreshCompanyScopedBoardData()
                        }
                    },
                    onSelectScreen: { appState.selectedScreen = $0 },
                    onSelectAgent: { agentId in
                        appState.selectedAgentId = agentId
                        appState.selectedScreen = .agents
                    },
                    onShowCreateIssue: { showingCreateIssueSheet = true },
                    onShowCreateAgentInfo: { showingCreateAgentInfoDialog = true }
                )

                companyDashboardContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(colors.background)
        .sheet(isPresented: $showingCreateCompanySheet) {
            CreateCompanySheet(
                onCreate: { name, description, budget, color, requireApproval in
                    _ = try await appState.createCompany(
                        name: name,
                        description: description,
                        budgetMonthlyCents: budget,
                        brandColor: color,
                        requireBoardApprovalForNewAgents: requireApproval
                    )
                }
            )
            .frame(width: 520, height: 420)
        }
        .sheet(isPresented: $showingCreateIssueSheet) {
            CreateIssueSheet(
                companyId: appState.selectedCompanyId,
                agents: appState.agents,
                projects: appState.projects,
                issues: appState.issues,
                onCreate: { params in
                    _ = try await appState.createIssue(params: params)
                    appState.selectedScreen = .issues
                }
            )
            .frame(width: 620, height: 520)
        }
        .overlay {
            if showingCreateProjectDialog {
                ZStack {
                    Color.black.opacity(0.56)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingCreateProjectDialog = false
                        }

                    CreateProjectDialog(
                        companyId: appState.selectedCompanyId,
                        goals: appState.goals,
                        onCreate: { params in
                            _ = try await appState.createProject(params: params)
                        },
                        onClose: {
                            showingCreateProjectDialog = false
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                .zIndex(10)
            }
        }
        .alert("Ask the CEO to create a new agent.", isPresented: $showingCreateAgentInfoDialog) {
            Button("OK", role: .cancel) {}
        }
        .task {
            if appState.isDaemonConnected, !appState.hasCompletedInitialCompanyLoad {
                await appState.loadBoardDataAsync()
            }
        }
    }

    @ViewBuilder
    private var companyDashboardContent: some View {
        switch appState.selectedScreen {
        case .dashboard:
            DashboardRoute()
        case .inbox:
            InboxRoute()
        case .workspaces:
            EmptyView()
        case .agents:
            AgentsRoute()
        case .issues:
            IssuesRoute(onShowCreateIssue: { showingCreateIssueSheet = true })
        case .approvals:
            ApprovalsRoute()
        case .projects:
            ProjectsRoute(onShowCreateProject: { showingCreateProjectDialog = true })
        case .goals:
            BoardPlaceholderRoute(
                title: "Goals",
                message: "The schema is in place. Goal service and UI parity are the next daemon port."
            )
        case .activity:
            BoardPlaceholderRoute(
                title: "Activity",
                message: "Activity logging is being persisted in SQLite. The native activity feed route is not wired yet."
            )
        case .costs:
            BoardPlaceholderRoute(
                title: "Costs",
                message: "Cost events are stored in SQLite. Cost summaries and charts are not exposed by daemon IPC yet."
            )
        case .settings:
            SettingsView()
        }
    }
}

private struct CompanyRail: View {
    @Environment(\.colorScheme) private var colorScheme

    let companies: [DaemonCompany]
    let selectedCompanyId: String?
    let selectedScreen: AppScreen
    let onSelectCompany: (String) -> Void
    let onGoToCompanyDashboard: (String) -> Void
    let onCreateCompany: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color(hex: "050505"))

                Text("u")
                    .font(GeistFont.sans(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "F5F5F5"))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "111111"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "1F1F1F"), lineWidth: 1)
                    )
            }
            .frame(height: 48)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.md) {
                    ForEach(companies) { company in
                        CompanyRailButton(
                            title: company.name,
                            monogram: String(company.name.prefix(1)).uppercased(),
                            colorHex: company.brandColor,
                            isSelected: selectedCompanyId == company.id,
                            onGoToDashboard: { onGoToCompanyDashboard(company.id) }
                        ) {
                            onSelectCompany(company.id)
                        }
                    }

                    Button(action: onCreateCompany) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "111111"))
                                .frame(width: 40, height: 40)
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "A3A3A3"))
                        }
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "1F1F1F"), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Create company")
                }
                .padding(.top, Spacing.md)
                .padding(.horizontal, Spacing.sm)
            }

            Spacer(minLength: 0)

            Button(action: onOpenSettings) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedScreen == .settings ? Color(hex: "141414") : Color.clear)
                        .frame(width: 40, height: 40)

                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selectedScreen == .settings ? Color(hex: "F5F5F5") : Color(hex: "8A8A8A"))
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, Spacing.lg)
            .help("Settings")
        }
        .frame(width: 64)
        .background(Color(hex: "050505"))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(hex: "1F1F1F"))
                .frame(width: BorderWidth.default)
        }
    }
}

private struct CompanyRailButton: View {
    let title: String
    let monogram: String
    let colorHex: String?
    let isSelected: Bool
    let onGoToDashboard: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(hex: colorHex ?? "262626"))
                    .frame(width: 40, height: 40)

                Text(monogram)
                    .font(GeistFont.sans(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .overlay(
                Circle()
                    .stroke(isSelected ? Color(hex: "F59E0B") : Color(hex: "1F1F1F"), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(title)
        .contextMenu {
            Button("Go to Dashboard", action: onGoToDashboard)
        }
    }
}

private struct CompanyDashboardSidebar: View {
    let selectedCompany: DaemonCompany?
    let agents: [DaemonAgent]
    let selectedScreen: AppScreen
    let selectedAgentId: String?
    let isLoading: Bool
    let boardError: String?
    let onRefresh: () -> Void
    let onSelectScreen: (AppScreen) -> Void
    let onSelectAgent: (String) -> Void
    let onShowCreateIssue: () -> Void
    let onShowCreateAgentInfo: () -> Void

    private let primarySections: [(String, [AppScreen])] = [
        ("Work", [.issues, .approvals, .workspaces]),
        ("Projects", [.projects, .goals]),
    ]

    private let companySection: (String, [AppScreen]) = ("Company", [.activity, .costs, .settings])

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedCompany?.name ?? "Company")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color(hex: "F5F5F5"))
                        .lineLimit(1)

                    Text(selectedCompany?.issuePrefix ?? "Local board")
                        .font(Typography.micro)
                        .foregroundStyle(Color(hex: "7A7A7A"))
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(hex: "F59E0B"))
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "8A8A8A"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 48)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        BoardSidebarButton(
                            title: "New Issue",
                            iconName: "plus",
                            isSelected: false,
                            action: onShowCreateIssue
                        )
                        BoardSidebarButton(
                            title: AppScreen.dashboard.title,
                            iconName: AppScreen.dashboard.iconName,
                            isSelected: selectedScreen == .dashboard,
                            action: { onSelectScreen(.dashboard) }
                        )
                        BoardSidebarButton(
                            title: AppScreen.inbox.title,
                            iconName: AppScreen.inbox.iconName,
                            isSelected: selectedScreen == .inbox,
                            action: { onSelectScreen(.inbox) }
                        )
                    }

                    ForEach(Array(primarySections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            sidebarSectionHeader(section.0)

                            ForEach(section.1, id: \.self) { route in
                                BoardSidebarButton(
                                    title: route.title,
                                    iconName: route.iconName,
                                    isSelected: selectedScreen == route,
                                    action: { onSelectScreen(route) }
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            sidebarSectionHeader("Agents")

                            Spacer()

                            Button(action: onShowCreateAgentInfo) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(hex: "8A8A8A"))
                                    .frame(width: 18, height: 18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(hex: "141414"))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Ask the CEO to create a new agent")
                            .padding(.trailing, Spacing.sm)
                        }
                        .padding(.top, Spacing.sm)

                        ForEach(agents) { agent in
                            AgentSidebarButton(
                                title: agent.name,
                                isSelected: selectedScreen == .agents && selectedAgentId == agent.id,
                                action: { onSelectAgent(agent.id) }
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        sidebarSectionHeader(companySection.0)

                        ForEach(companySection.1, id: \.self) { route in
                            BoardSidebarButton(
                                title: route.title,
                                iconName: route.iconName,
                                isSelected: selectedScreen == route,
                                action: { onSelectScreen(route) }
                            )
                        }
                    }
                }
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }

            if let boardError, !boardError.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Board error")
                        .font(Typography.micro)
                        .foregroundStyle(Color(hex: "F87171"))
                    Text(boardError)
                        .font(Typography.micro)
                        .foregroundStyle(Color(hex: "7A7A7A"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            }
        }
        .frame(width: 220)
        .background(Color(hex: "0A0A0A"))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(hex: "1F1F1F"))
                .frame(width: BorderWidth.default)
        }
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typography.micro)
            .foregroundStyle(Color(hex: "666666"))
            .padding(.horizontal, Spacing.md)
    }
}

private struct BoardSidebarButton: View {
    let title: String
    let iconName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 14)
                Text(title)
                    .font(GeistFont.sans(size: FontSize.smMd, weight: .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color(hex: "F5F5F5") : Color(hex: "A3A3A3"))
            .padding(.horizontal, Spacing.md)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(hex: "141414") : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(hex: "1F1F1F") : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}

private struct AgentSidebarButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(title)
                    .font(GeistFont.sans(size: FontSize.smMd, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color(hex: "E5E5E5") : Color(hex: "B3B3B3"))
            .padding(.horizontal, Spacing.md)
            .frame(height: 24)
            .padding(.horizontal, Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var openIssuesCount: Int {
        appState.issues.filter { $0.completedAt == nil && $0.cancelledAt == nil && $0.hiddenAt == nil }.count
    }

    var body: some View {
        ScrollView {
            if let company = appState.selectedCompany {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Dashboard")
                            .font(Typography.caption)
                            .foregroundStyle(colors.primary)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(company.name)
                                    .font(Typography.pageTitle)
                                if let description = company.description, !description.isEmpty {
                                    Text(description)
                                        .font(Typography.body)
                                        .foregroundStyle(colors.mutedForeground)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer()
                            StatusPill(text: company.status)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.md)], spacing: Spacing.md) {
                        DashboardMetricCard(title: "Issue Prefix", value: company.issuePrefix, footnote: "Next #\(company.issueCounter + 1)")
                        DashboardMetricCard(title: "Open Issues", value: "\(openIssuesCount)", footnote: "\(appState.issues.count) total")
                        DashboardMetricCard(title: "Agents", value: "\(appState.agents.count)", footnote: company.ceoAgentId == nil ? "CEO missing" : "CEO ready")
                        DashboardMetricCard(title: "Live Workspaces", value: "\(appState.workspaces.count)", footnote: appState.workspaces.isEmpty ? "No active coding sessions" : "Issue-owned only")
                        DashboardMetricCard(title: "Projects", value: "\(appState.projects.count)", footnote: "Main repo anchors")
                        DashboardMetricCard(title: "Monthly Budget", value: money(company.budgetMonthlyCents), footnote: "Spent \(money(company.spentMonthlyCents))")
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Spacing.md)], spacing: Spacing.md) {
                        DashboardSurfaceCard(title: "Agents") {
                            if appState.agents.isEmpty {
                                DashboardEmptyText("Agents will appear here after the CEO hires them.")
                            } else {
                                ForEach(appState.agents.prefix(5)) { agent in
                                    DashboardLineItem(
                                        title: agent.name,
                                        subtitle: agent.title ?? agent.role,
                                        trailing: agent.status
                                    )
                                }
                            }
                        }

                        DashboardSurfaceCard(title: "Projects") {
                            if appState.projects.isEmpty {
                                DashboardEmptyText("Projects define the main repo path for workspaces.")
                            } else {
                                ForEach(appState.projects.prefix(5)) { project in
                                    DashboardLineItem(
                                        title: project.name,
                                        subtitle: project.primaryWorkspace?.cwd ?? "Missing repo path",
                                        trailing: project.status
                                    )
                                }
                            }
                        }
                    }

                    DashboardSurfaceCard(title: "Recent Issues") {
                        if appState.issues.isEmpty {
                            DashboardEmptyText("Issues drive workspaces. Create one to start agent work.")
                        } else {
                            ForEach(appState.issues.prefix(8)) { issue in
                                Button {
                                    appState.selectedIssueId = issue.id
                                    appState.selectedScreen = .issues
                                } label: {
                                    DashboardLineItem(
                                        title: issue.identifier ?? issue.title,
                                        subtitle: issue.title,
                                        trailing: issue.workspaceSessionId == nil ? issue.status : "workspace"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    DashboardSurfaceCard(title: "Active Workspaces") {
                        if appState.workspaces.isEmpty {
                            DashboardEmptyText("Agent-created coding sessions appear here once work begins on an issue.")
                        } else {
                            ForEach(appState.workspaces.prefix(6)) { workspace in
                                Button {
                                    appState.selectedBoardWorkspaceId = workspace.id
                                    appState.selectedScreen = .workspaces
                                } label: {
                                    DashboardLineItem(
                                        title: workspace.issueIdentifier ?? workspace.title,
                                        subtitle: [workspace.issueTitle, workspace.projectName, workspace.agentName]
                                            .compactMap { $0 }
                                            .joined(separator: " · "),
                                        trailing: workspace.workspaceStatus
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Spacing.xxl)
            } else {
                BoardEmptyState(
                    title: "Select a company",
                    message: "Choose a company from the rail to view its dashboard."
                )
            }
        }
        .background(colors.background)
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Color(hex: "8A8A8A"))
            Text(value)
                .font(Typography.h2)
                .foregroundStyle(Color(hex: "F5F5F5"))
            Text(footnote)
                .font(Typography.micro)
                .foregroundStyle(Color(hex: "6B6B6B"))
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color(hex: "111111"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "1F1F1F"), lineWidth: 1)
        )
    }
}

private struct DashboardSurfaceCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(Typography.h4)
                .foregroundStyle(Color(hex: "F5F5F5"))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color(hex: "111111"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "1F1F1F"), lineWidth: 1)
        )
    }
}

private struct DashboardLineItem: View {
    let title: String
    let subtitle: String
    let trailing: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color(hex: "F5F5F5"))
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Color(hex: "7A7A7A"))
                    .lineLimit(2)
            }
            Spacer()
            Text(trailing.replacingOccurrences(of: "_", with: " "))
                .font(Typography.micro)
                .foregroundStyle(Color(hex: "A3A3A3"))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(Color(hex: "181818"))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardEmptyText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(Typography.body)
            .foregroundStyle(Color(hex: "7A7A7A"))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct InboxRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var visibleIssues: [DaemonIssue] {
        appState.issues.filter { $0.hiddenAt == nil }
    }

    private var pendingApprovals: [DaemonApproval] {
        appState.approvals
            .filter { $0.status == "pending" }
            .sorted {
                (parsedDate($0.updatedAt) ?? .distantPast) > (parsedDate($1.updatedAt) ?? .distantPast)
            }
    }

    private var approvalFeedItems: [InboxFeedItem] {
        pendingApprovals.map { approval in
            InboxFeedItem(
                id: "approval-\(approval.id)",
                timestamp: parsedDate(approval.updatedAt) ?? .distantPast,
                title: approval.approvalType.replacingOccurrences(of: "_", with: " ").capitalized,
                subtitle: "Pending approval · \(formatDate(approval.updatedAt))",
                trailingLabel: approval.status,
                target: .approval(approval.id)
            )
        }
    }

    private var issueActivityFeedItems: [InboxFeedItem] {
        visibleIssues.flatMap { issue in
            var items: [InboxFeedItem] = []
            let issueTitle = issue.identifier ?? issue.title

            if let comments = appState.issueComments[issue.id] {
                items.append(contentsOf: comments.map { comment in
                    InboxFeedItem(
                        id: "comment-\(comment.id)",
                        timestamp: parsedDate(comment.createdAt) ?? .distantPast,
                        title: issueTitle,
                        subtitle: "\(formatDate(comment.createdAt)) · \(comment.body)",
                        trailingLabel: "comment",
                        target: .issue(issue.id)
                    )
                })
            }

            items.append(
                InboxFeedItem(
                    id: "issue-update-\(issue.id)",
                    timestamp: parsedDate(issue.updatedAt) ?? .distantPast,
                    title: issueTitle,
                    subtitle: "\(formatDate(issue.updatedAt)) · \(issueActivitySummary(issue))",
                    trailingLabel: issue.status,
                    target: .issue(issue.id)
                )
            )

            return items
        }
    }

    private var feedItems: [InboxFeedItem] {
        Array((approvalFeedItems + issueActivityFeedItems).sorted { $0.timestamp > $1.timestamp }.prefix(50))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Inbox")
                        .font(Typography.caption)
                        .foregroundStyle(colors.primary)
                    Text("Approvals and recent issue activity")
                        .font(Typography.pageTitle)
                }

                DashboardSurfaceCard(title: "Inbox") {
                    if feedItems.isEmpty {
                        DashboardEmptyText("Pending approvals and recent issue activity will appear here.")
                    } else {
                        ForEach(feedItems) { item in
                            Button {
                                open(item)
                            } label: {
                                DashboardLineItem(
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    trailing: item.trailingLabel
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .background(colors.background)
        .task(id: appState.selectedCompanyId) {
            await preloadIssueComments()
        }
    }

    private func preloadIssueComments() async {
        for issue in visibleIssues where appState.issueComments[issue.id] == nil {
            await appState.refreshIssueComments(issueId: issue.id)
        }
    }

    private func open(_ item: InboxFeedItem) {
        switch item.target {
        case .approval(let approvalId):
            appState.selectedApprovalId = approvalId
            appState.selectedScreen = .approvals
        case .issue(let issueId):
            appState.selectedIssueId = issueId
            appState.selectedScreen = .issues
        }
    }

    private func issueActivitySummary(_ issue: DaemonIssue) -> String {
        if issue.completedAt != nil {
            return "Issue completed"
        }
        if issue.cancelledAt != nil {
            return "Issue cancelled"
        }
        if issue.startedAt != nil {
            return "Work started"
        }
        if issue.workspaceSessionId != nil {
            return "Workspace attached"
        }
        return "Issue updated"
    }
}

private enum InboxFeedTarget {
    case approval(String)
    case issue(String)
}

private struct InboxFeedItem: Identifiable {
    let id: String
    let timestamp: Date
    let title: String
    let subtitle: String
    let trailingLabel: String
    let target: InboxFeedTarget
}

struct CreateFirstCompanyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = ""
    @State private var description = ""
    @State private var budget = ""
    @State private var brandColor = "#0F766E"
    @State private var requireApproval = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ZStack {
            colors.background
                .ignoresSafeArea()

            VStack(spacing: Spacing.xxl) {
                VStack(spacing: Spacing.sm) {
                    Text("Set up your first company")
                        .font(Typography.pageTitle)
                        .foregroundStyle(colors.foreground)

                    Text("Your device is ready. Create a company to unlock the dashboard, bootstrap the CEO, and create the local agent file structure beside `unbound.sqlite`.")
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    TextField("Company Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                    TextField("Monthly Budget (cents)", text: $budget)
                    TextField("Brand Color", text: $brandColor)
                    Toggle("Require approval for new agents", isOn: $requireApproval)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Typography.caption)
                            .foregroundStyle(colors.destructive)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Create Company")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(Spacing.xl)
                .background(Color(hex: "111111"))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(hex: "1F1F1F"), lineWidth: 1)
                )
                .frame(width: 520)
            }
            .padding(Spacing.xxxl)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await appState.createCompany(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.nonEmpty,
                budgetMonthlyCents: Int(budget),
                brandColor: brandColor.nonEmpty,
                requireBoardApprovalForNewAgents: requireApproval
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InitialCompanyLoadErrorView: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: String
    let onRetry: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(colors.destructive)

            VStack(spacing: Spacing.sm) {
                Text("Unable to load companies")
                    .font(Typography.title2)
                    .foregroundStyle(colors.foreground)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }
}

private struct AgentsRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var orderedAgents: [DaemonAgent] {
        sidebarOrderedAgents(appState.agents, ceoAgentId: appState.selectedCompany?.ceoAgentId)
    }

    private var selectedAgent: DaemonAgent? {
        appState.selectedAgent ?? orderedAgents.first
    }

    var body: some View {
        ScrollView {
            if let agent = selectedAgent {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Agent")
                            .font(Typography.caption)
                            .foregroundStyle(colors.primary)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text(agent.name)
                                    .font(Typography.pageTitle)
                                if let title = agent.title, !title.isEmpty {
                                    Text(title)
                                        .font(Typography.body)
                                        .foregroundStyle(colors.mutedForeground)
                                }
                            }
                            Spacer()
                            StatusPill(text: agent.status)
                        }
                    }

                    DetailGrid(items: [
                        ("Role", agent.role),
                        ("Adapter", agent.adapterType),
                        ("Reports To", agent.reportsTo ?? "CEO"),
                        ("Home", agent.homePath ?? "Missing"),
                        ("Instructions", agent.instructionsPath ?? "Missing"),
                        ("Monthly Budget", money(agent.budgetMonthlyCents))
                    ])

                    if let capabilities = agent.capabilities, !capabilities.isEmpty {
                        DetailSection(title: "Capabilities", text: capabilities)
                    }

                    if let metadata = agent.metadata, !metadata.isEmpty {
                        DetailSection(title: "Metadata", text: anyCodableDictionaryText(metadata))
                    }
                }
                .padding(Spacing.xl)
            } else {
                BoardEmptyState(
                    title: "No agents in this company",
                    message: "Agents will appear here after the CEO creates them."
                )
            }
        }
        .background(colors.background)
        .task(id: appState.selectedCompanyId) {
            ensureSelectedAgentIfNeeded()
        }
        .task(id: appState.selectedAgentId) {
            ensureSelectedAgentIfNeeded()
        }
    }

    private func ensureSelectedAgentIfNeeded() {
        guard appState.selectedAgentId == nil || appState.selectedAgent == nil else { return }
        appState.selectedAgentId = orderedAgents.first?.id
    }
}

private struct ProjectsRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let onShowCreateProject: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var currentProject: DaemonProject? {
        appState.selectedProject ?? appState.projects.first
    }

    private func goalTitle(for goalId: String?) -> String {
        guard let goalId else { return "None" }
        return appState.goals.first(where: { $0.id == goalId })?.title ?? goalId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Projects")
                            .font(Typography.caption)
                            .foregroundStyle(colors.primary)
                        Text("Repo anchors and ownership")
                            .font(Typography.pageTitle)
                    }

                    Spacer()

                    Button {
                        onShowCreateProject()
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                DashboardSurfaceCard(title: "Projects") {
                    if appState.projects.isEmpty {
                        DashboardEmptyText("Projects define the main repo anchor that issue workspaces run inside.")
                    } else {
                        ForEach(appState.projects) { project in
                            DashboardSelectableLineButton(
                                title: project.name,
                                subtitle: project.primaryWorkspace?.cwd ?? "Missing repo path",
                                trailing: project.status,
                                isSelected: currentProject?.id == project.id,
                                action: { appState.selectedProjectId = project.id }
                            )
                        }
                    }
                }

                if let project = currentProject {
                    DashboardSurfaceCard(title: "Project Details") {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            Text(project.name)
                                .font(Typography.h3)
                                .foregroundStyle(Color(hex: "F5F5F5"))

                            if let description = project.description, !description.isEmpty {
                                DetailSection(title: "Description", text: description)
                            }

                            DetailGrid(items: [
                                ("Status", project.status),
                                ("Lead Agent", project.leadAgentId ?? "Unassigned"),
                                ("Goal", goalTitle(for: project.goalId)),
                                ("Repo Path", project.primaryWorkspace?.cwd ?? "Missing"),
                                ("Repo URL", project.primaryWorkspace?.repoUrl ?? "Local only"),
                                ("Repo Ref", project.primaryWorkspace?.repoRef ?? "main")
                            ])
                        }
                    }
                } else {
                    BoardEmptyState(
                        title: "Select a project",
                        message: "Project repo-anchor configuration appears here."
                    )
                }
            }
            .padding(Spacing.xl)
        }
        .background(colors.background)
    }
}

private struct IssuesRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let onShowCreateIssue: () -> Void

    @State private var newCommentBody = ""

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var selectedIssue: DaemonIssue? {
        appState.selectedIssue ?? appState.issues.first
    }

    private var subissues: [DaemonIssue] {
        guard let selectedIssue else { return [] }
        return appState.issues.filter { $0.parentId == selectedIssue.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Issues")
                            .font(Typography.caption)
                            .foregroundStyle(colors.primary)
                        Text("Execution queue")
                            .font(Typography.pageTitle)
                    }

                    Spacer()

                    Button {
                        onShowCreateIssue()
                    } label: {
                        Label("New Issue", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                DashboardSurfaceCard(title: "Issues") {
                    if appState.issues.isEmpty {
                        DashboardEmptyText("Issues own workspaces. Agents create coding sessions automatically when work starts.")
                    } else {
                        ForEach(appState.issues) { issue in
                            DashboardSelectableLineButton(
                                title: issue.identifier ?? issue.title,
                                subtitle: issue.title,
                                trailing: issue.workspaceSessionId == nil ? issue.status : "workspace",
                                isSelected: selectedIssue?.id == issue.id,
                                leadingPadding: CGFloat(issue.requestDepth) * 12,
                                action: {
                                    appState.selectedIssueId = issue.id
                                    Task { await appState.refreshIssueComments(issueId: issue.id) }
                                }
                            )
                        }
                    }
                }

                if let issue = selectedIssue {
                    DashboardSurfaceCard(title: "Issue Details") {
                        VStack(alignment: .leading, spacing: Spacing.xl) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(issue.identifier ?? issue.title)
                                        .font(Typography.caption)
                                        .foregroundStyle(colors.primary)
                                    Text(issue.title)
                                        .font(Typography.h3)
                                        .foregroundStyle(Color(hex: "F5F5F5"))
                                }
                                Spacer()
                                if issue.assigneeAgentId != nil && issue.projectId != nil {
                                    Button {
                                        Task {
                                            do {
                                                _ = try await appState.checkoutIssue(issueId: issue.id)
                                            } catch {
                                                boardLogger.error("Failed to start workspace for issue \(issue.id): \(error)")
                                            }
                                        }
                                    } label: {
                                        Label("Start Workspace", systemImage: "play.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            if let description = issue.description, !description.isEmpty {
                                DetailSection(title: "Description", text: description)
                            }

                            DetailGrid(items: [
                                ("Status", issue.status),
                                ("Priority", issue.priority),
                                ("Project", issue.projectId ?? "Unassigned"),
                                ("Assignee", issue.assigneeAgentId ?? "Unassigned"),
                                ("Parent", issue.parentId ?? "None"),
                                ("Depth", "\(issue.requestDepth)")
                            ])

                            if !subissues.isEmpty {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    Text("Subissues")
                                        .font(Typography.h4)
                                        .foregroundStyle(Color(hex: "F5F5F5"))
                                    ForEach(subissues) { child in
                                        HStack {
                                            Text(child.identifier ?? child.title)
                                            Spacer()
                                            StatusPill(text: child.status)
                                        }
                                        .padding(.vertical, Spacing.xxs)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Comments")
                                    .font(Typography.h4)
                                    .foregroundStyle(Color(hex: "F5F5F5"))

                                let comments = appState.issueComments[issue.id] ?? []
                                if comments.isEmpty {
                                    Text("No comments yet.")
                                        .font(Typography.body)
                                        .foregroundStyle(colors.mutedForeground)
                                } else {
                                    ForEach(comments) { comment in
                                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                                            Text(comment.body)
                                                .font(Typography.body)
                                            Text(formatDate(comment.createdAt))
                                                .font(Typography.micro)
                                                .foregroundStyle(colors.mutedForeground)
                                        }
                                        .padding(Spacing.md)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(colors.card)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                    }
                                }

                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    TextEditor(text: $newCommentBody)
                                        .frame(minHeight: 120)
                                        .padding(Spacing.sm)
                                        .background(colors.card)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                                    Button("Add Comment") {
                                        let body = newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !body.isEmpty else { return }
                                        Task {
                                            do {
                                                _ = try await appState.addIssueComment(
                                                    params: [
                                                        "company_id": issue.companyId,
                                                        "issue_id": issue.id,
                                                        "body": body,
                                                    ]
                                                )
                                                newCommentBody = ""
                                            } catch {
                                                boardLogger.error("Failed to add issue comment: \(error)")
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                } else {
                    BoardEmptyState(
                        title: "Select an issue",
                        message: "Comments, subissues, approvals, and workspace status show here."
                    )
                }
            }
            .padding(Spacing.xl)
        }
        .background(colors.background)
        .task(id: selectedIssue?.id) {
            if let issue = selectedIssue {
                await appState.refreshIssueComments(issueId: issue.id)
            }
        }
    }
}

private struct ApprovalsRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var currentApproval: DaemonApproval? {
        appState.selectedApproval ?? appState.approvals.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Approvals")
                        .font(Typography.caption)
                        .foregroundStyle(colors.primary)
                    Text("Decision queue")
                        .font(Typography.pageTitle)
                }

                DashboardSurfaceCard(title: "Approvals") {
                    if appState.approvals.isEmpty {
                        DashboardEmptyText("Hire approvals and issue-linked approvals will appear here.")
                    } else {
                        ForEach(appState.approvals) { approval in
                            DashboardSelectableLineButton(
                                title: approval.approvalType,
                                subtitle: formatDate(approval.createdAt),
                                trailing: approval.status,
                                isSelected: currentApproval?.id == approval.id,
                                action: { appState.selectedApprovalId = approval.id }
                            )
                        }
                    }
                }

                if let approval = currentApproval {
                    DashboardSurfaceCard(title: "Approval Details") {
                        VStack(alignment: .leading, spacing: Spacing.xl) {
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(approval.approvalType)
                                        .font(Typography.h3)
                                        .foregroundStyle(Color(hex: "F5F5F5"))
                                    Text("Status: \(approval.status)")
                                        .font(Typography.caption)
                                        .foregroundStyle(colors.mutedForeground)
                                }
                                Spacer()
                                if approval.status == "pending" {
                                    Button {
                                        Task {
                                            do {
                                                _ = try await appState.approveApproval(approvalId: approval.id)
                                            } catch {
                                                boardLogger.error("Failed to approve \(approval.id): \(error)")
                                            }
                                        }
                                    } label: {
                                        Label("Approve", systemImage: "checkmark")
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            DetailGrid(items: [
                                ("Requested By Agent", approval.requestedByAgentId ?? "System"),
                                ("Requested By User", approval.requestedByUserId ?? "Local Board"),
                                ("Decided By", approval.decidedByUserId ?? "Pending"),
                                ("Created", formatDate(approval.createdAt)),
                                ("Updated", formatDate(approval.updatedAt))
                            ])

                            if let payload = approval.payload, !payload.isEmpty {
                                DetailSection(title: "Payload", text: anyCodableDictionaryText(payload))
                            }
                        }
                    }
                } else {
                    BoardEmptyState(
                        title: "Select an approval",
                        message: "Approval payloads and decisions show here."
                    )
                }
            }
            .padding(Spacing.xl)
        }
        .background(colors.background)
    }
}

private struct DashboardSelectableLineButton: View {
    let title: String
    let subtitle: String
    let trailing: String
    let isSelected: Bool
    let leadingPadding: CGFloat
    let action: () -> Void

    init(
        title: String,
        subtitle: String,
        trailing: String,
        isSelected: Bool,
        leadingPadding: CGFloat = 0,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.isSelected = isSelected
        self.leadingPadding = leadingPadding
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            DashboardLineItem(title: title, subtitle: subtitle, trailing: trailing)
                .padding(.leading, leadingPadding)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color(hex: "181818") : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color(hex: "262626") : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct BoardWorkspacesRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var chatInput = ""
    @State private var selectedModel: AIModel = .opus
    @State private var selectedThinkMode: ThinkMode = .none
    @State private var isPlanMode = false
    @State private var fileTreeViewModel: FileTreeViewModel?
    @State private var gitViewModel = GitViewModel()
    @State private var selectedSidebarTab: RightSidebarTab = .changes
    @State private var editorState = EditorState()
    @State private var workspaceTabState = WorkspaceTabState()

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var selectedWorkspace: DaemonWorkspace? {
        appState.selectedBoardWorkspace ?? appState.workspaces.first
    }

    private var selectedSession: Session? {
        appState.selectedSession
    }

    private var selectedRepository: Repository? {
        appState.selectedRepository
    }

    private var workingDirectoryPath: String? {
        resolvedWorkingDirectoryPath(for: selectedSession)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if appState.workspaces.isEmpty {
                    BoardEmptyState(
                        title: "No active workspaces",
                        message: "Workspaces appear automatically when an assigned agent starts an issue."
                    )
                } else {
                    List(appState.workspaces, selection: Binding(
                        get: { appState.selectedBoardWorkspaceId },
                        set: { newValue in
                            guard let newValue,
                                  let workspace = appState.workspaces.first(where: { $0.id == newValue }) else {
                                return
                            }
                            Task { await appState.selectBoardWorkspace(workspace) }
                        }
                    )) { workspace in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack {
                                Text(workspace.issueIdentifier ?? workspace.title)
                                Spacer()
                                StatusPill(text: workspace.workspaceStatus)
                            }
                            Text(workspace.issueTitle ?? workspace.title)
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                            Text([
                                workspace.projectName,
                                workspace.agentName,
                            ].compactMap { $0 }.joined(separator: " · "))
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 300, idealWidth: 340)

            VStack(spacing: 0) {
                if appState.isGhInstalled == false {
                    GhMissingBanner()
                }

                if let workspace = selectedWorkspace,
                   let session = selectedSession,
                   let repository = selectedRepository {
                    workspaceSummaryHeader(workspace)
                    ChatPanel(
                        session: session,
                        repository: repository,
                        chatInput: $chatInput,
                        selectedModel: $selectedModel,
                        selectedThinkMode: $selectedThinkMode,
                        isPlanMode: $isPlanMode,
                        editorState: editorState,
                        workspaceTabState: workspaceTabState
                    )
                } else if let workspace = selectedWorkspace {
                    workspaceFallbackDetail(workspace)
                } else {
                    BoardEmptyState(
                        title: "Select a workspace",
                        message: "Issue-owned coding sessions appear here. The main repo path is used directly."
                    )
                }
            }
            .frame(minWidth: 420, idealWidth: 700, maxWidth: .infinity)

            VStack(spacing: 0) {
                if let workspace = selectedWorkspace {
                    WorkspaceInspector(workspace: workspace)
                    ShadcnDivider()
                }

                RightSidebarPanel(
                    fileTreeViewModel: fileTreeViewModel,
                    gitViewModel: gitViewModel,
                    editorState: editorState,
                    selectedTab: $selectedSidebarTab,
                    workingDirectory: workingDirectoryPath
                )
            }
            .frame(minWidth: 320, idealWidth: 380)
        }
        .background(colors.background)
        .task {
            initializeFileTreeViewModelIfNeeded()
            if appState.selectedBoardWorkspaceId == nil, let first = appState.workspaces.first {
                await appState.selectBoardWorkspace(first)
            }
            syncWorkspaceTabState()
        }
        .onChange(of: appState.selectedSession?.id) { _, newSessionId in
            Task { @MainActor in
                fileTreeViewModel?.setSessionId(newSessionId)
                if selectedSidebarTab == .files {
                    await fileTreeViewModel?.loadRoot()
                }
                syncWorkspaceTabState()
            }
        }
        .onChange(of: workingDirectoryPath) { _, _ in
            syncWorkspaceTabState()
        }
    }

    private func workspaceSummaryHeader(_ workspace: DaemonWorkspace) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(workspace.issueIdentifier ?? "Workspace")
                    .font(Typography.caption)
                    .foregroundStyle(colors.primary)
                Text(workspace.issueTitle ?? workspace.title)
                    .font(Typography.h3)
                Text([
                    workspace.projectName,
                    workspace.agentName,
                    workspace.workspaceBranch,
                ].compactMap { $0 }.joined(separator: " · "))
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
            }
            Spacer()
            StatusPill(text: workspace.workspaceStatus)
        }
        .padding(Spacing.lg)
        .background(colors.toolbarBackground)
    }

    private func workspaceFallbackDetail(_ workspace: DaemonWorkspace) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                workspaceSummaryHeader(workspace)
                DetailSection(
                    title: "Session",
                    text: "The issue-owned coding session exists in the daemon, but the legacy session cache has not hydrated it into the chat shell yet."
                )
                DetailGrid(items: [
                    ("Session ID", workspace.sessionId),
                    ("Repository ID", workspace.repositoryId),
                    ("Repo Path", workspace.workspaceRepoPath ?? "Missing"),
                    ("Branch", workspace.workspaceBranch ?? "main")
                ])
            }
            .padding(Spacing.lg)
        }
    }

    private func initializeFileTreeViewModelIfNeeded() {
        guard fileTreeViewModel == nil else { return }
        fileTreeViewModel = FileTreeViewModel()
        fileTreeViewModel?.setSessionId(selectedSession?.id)
    }

    private func syncWorkspaceTabState() {
        workspaceTabState.resetForSession(
            selectedSession?.id,
            workspacePath: workingDirectoryPath
        )
    }

    private func resolvedWorkingDirectoryPath(for session: Session?) -> String? {
        guard let session else { return nil }

        if session.isWorktree, let worktreePath = session.worktreePath {
            return FileManager.default.fileExists(atPath: worktreePath) ? worktreePath : nil
        }

        guard let repositoryPath = appState.repositories.first(where: { $0.id == session.repositoryId })?.path else {
            return nil
        }

        return FileManager.default.fileExists(atPath: repositoryPath) ? repositoryPath : nil
    }
}

private struct WorkspaceInspector: View {
    @Environment(\.colorScheme) private var colorScheme

    let workspace: DaemonWorkspace

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Workspace Details")
                .font(Typography.h4)

            DetailGrid(items: [
                ("Issue", workspace.issueIdentifier ?? workspace.issueId ?? "Missing"),
                ("Agent", workspace.agentName ?? workspace.agentId ?? "Missing"),
                ("Project", workspace.projectName ?? workspace.projectId ?? "Missing"),
                ("Branch", workspace.workspaceBranch ?? "main"),
                ("Repo", workspace.workspaceRepoPath ?? "Missing")
            ])

            if let metadata = workspace.workspaceMetadata, !metadata.isEmpty {
                DetailSection(title: "Metadata", text: anyCodableDictionaryText(metadata))
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.background)
    }
}

private struct BoardPlaceholderRoute: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        BoardEmptyState(title: title, message: message)
            .background(colors.background)
    }
}

private struct BoardListPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let actionTitle: String?
    let onAction: (() -> Void)?
    let content: Content

    init(
        title: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.content = content()
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(Typography.h4)
                Spacer()
                if let actionTitle, let onAction {
                    Button(actionTitle, action: onAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(Spacing.lg)
            .background(colors.toolbarBackground)

            ShadcnDivider()
            content
        }
    }
}

private struct BoardEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    var action: (() -> Void)? = nil

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(colors.mutedForeground)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.h4)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            if let action {
                Button("Create") {
                    action()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

private struct BoardMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(Typography.micro)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Typography.bodySmall)
        }
    }
}

private struct DetailGrid: View {
    let items: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], spacing: Spacing.md) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(item.0)
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(Typography.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct DetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.h4)
            Text(text)
                .font(Typography.body)
                .textSelection(.enabled)
        }
    }
}

private struct StatusPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Text(text.replacingOccurrences(of: "_", with: " "))
            .font(Typography.micro)
            .foregroundStyle(colors.primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(colors.secondary)
            .clipShape(Capsule())
    }
}

private struct CreateCompanySheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (String, String?, Int?, String?, Bool?) async throws -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var budget = ""
    @State private var brandColor = "#0F766E"
    @State private var requireApproval = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Company Name", text: $name)
            TextField("Description", text: $description, axis: .vertical)
            TextField("Monthly Budget (cents)", text: $budget)
            TextField("Brand Color", text: $brandColor)
            Toggle("Require approval for new agents", isOn: $requireApproval)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Company") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.lg)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await onCreate(
                name.trimmingCharacters(in: .whitespacesAndNewlines),
                description.nonEmpty,
                Int(budget),
                brandColor.nonEmpty,
                requireApproval
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CreateAgentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let companyId: String?
    let defaultReportsTo: String?
    let onCreate: ([String: Any]) async throws -> Void

    @State private var name = ""
    @State private var role = "general"
    @State private var title = ""
    @State private var icon = "person.crop.circle"
    @State private var adapterType = "process"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Role", text: $role)
            TextField("Title", text: $title)
            TextField("Icon", text: $icon)
            TextField("Adapter Type", text: $adapterType)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Agent") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companyId == nil)
            }
        }
        .padding(Spacing.lg)
    }

    private func save() async {
        guard let companyId else { return }

        isSaving = true
        defer { isSaving = false }

        var params: [String: Any] = [
            "company_id": companyId,
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "role": role.trimmingCharacters(in: .whitespacesAndNewlines),
            "adapter_type": adapterType.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if let defaultReportsTo {
            params["reports_to"] = defaultReportsTo
        }
        if let title = title.nonEmpty {
            params["title"] = title
        }
        if let icon = icon.nonEmpty {
            params["icon"] = icon
        }

        do {
            try await onCreate(params)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CreateProjectDialog: View {
    let companyId: String?
    let goals: [DaemonGoal]
    let onCreate: ([String: Any]) async throws -> Void
    let onClose: () -> Void

    @State private var repoPath = ""
    @State private var selectedStatus = "planned"
    @State private var selectedGoalId = ""
    @State private var targetDate: Date?
    @State private var showingDatePopover = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var derivedProjectName: String {
        let trimmedPath = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmedPath).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedGoal: DaemonGoal? {
        goals.first { $0.id == selectedGoalId }
    }

    private var canCreate: Bool {
        companyId != nil && !derivedProjectName.isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("PRO")
                        .font(GeistFont.sans(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "8D8D8D"))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "1F1F1F"))
                        )

                    Text("New project")
                        .font(GeistFont.sans(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: "D8D8D8"))
                }

                Spacer()

                Button(action: onClose) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.clear)
                            .frame(width: 32, height: 32)

                        Text("✕")
                            .font(GeistFont.sans(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "9A9A9A"))
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(hex: "1D1D1D"))
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 18) {
                Rectangle()
                    .fill(Color(hex: "1A1A1A"))
                    .frame(height: 1)

                HStack(alignment: .center, spacing: 10) {
                    HStack {
                        Text(repoPath.isEmpty ? "Choose a project folder" : repoPath)
                            .font(GeistFont.sans(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: repoPath.isEmpty ? "7A7A7A" : "C8C8C8"))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "0A0A0A"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "2A2A2A"), lineWidth: 1)
                    )

                    Button(action: chooseFolder) {
                        Text("Choose folder")
                            .font(GeistFont.sans(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "F1F1F1"))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(hex: "141414"))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(hex: "343434"), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(Color.red.opacity(0.92))
                }

                HStack(alignment: .center, spacing: 0) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(["planned", "active", "completed"], id: \.self) { status in
                                Button(status) {
                                    selectedStatus = status
                                }
                            }
                        } label: {
                            ProjectDialogChip(
                                text: selectedStatus,
                                textColor: projectDialogStatusColor(selectedStatus)
                            )
                        }
                        .menuStyle(BorderlessButtonMenuStyle())

                        Menu {
                            if goals.isEmpty {
                                Button("No goals yet") {}
                                    .disabled(true)
                            } else {
                                Button("Clear Goal") {
                                    selectedGoalId = ""
                                }

                                Divider()

                                ForEach(goals) { goal in
                                    Button(goal.title) {
                                        selectedGoalId = goal.id
                                    }
                                }
                            }
                        } label: {
                            ProjectDialogChip(
                                iconText: "◎",
                                text: selectedGoal?.title ?? "Goal",
                                textColor: Color(hex: selectedGoal == nil ? "9A9A9A" : "D8D8D8")
                            )
                        }
                        .menuStyle(BorderlessButtonMenuStyle())

                        Button {
                            showingDatePopover = true
                        } label: {
                            ProjectDialogChip(
                                iconText: "◫",
                                text: projectDialogDateLabel(targetDate),
                                textColor: Color(hex: targetDate == nil ? "9A9A9A" : "D8D8D8")
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingDatePopover, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Target date")
                                    .font(Typography.caption)
                                    .foregroundStyle(Color(hex: "A1A1A1"))

                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { targetDate ?? Date() },
                                        set: { targetDate = $0 }
                                    ),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.graphical)
                                .labelsHidden()

                                HStack {
                                    Button("Clear") {
                                        targetDate = nil
                                        showingDatePopover = false
                                    }
                                    .disabled(targetDate == nil)

                                    Spacer()

                                    Button("Done") {
                                        showingDatePopover = false
                                    }
                                    .keyboardShortcut(.defaultAction)
                                }
                            }
                            .padding(16)
                            .frame(width: 280)
                        }
                    }

                    Spacer(minLength: 16)

                    Button {
                        Task { await save() }
                    } label: {
                        Text(isSaving ? "Creating..." : "Create project")
                            .font(GeistFont.sans(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: canCreate ? "2B2B2B" : "5B5B5B"))
                            .padding(.vertical, 11)
                            .padding(.horizontal, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color(hex: canCreate ? "B8B8B8" : "4A4A4A"))
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                }
                .padding(.top, 4)
            }
            .padding(.top, 18)
            .padding(.leading, 18)
            .padding(.bottom, 16)
            .padding(.trailing, 18)
        }
        .frame(width: 509)
        .background(Color(hex: "050505"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "242424"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.40), radius: 24, x: 0, y: 24)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose folder"
        panel.message = "Select the main repository folder for this project"

        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
            errorMessage = nil
        }
    }

    private func save() async {
        guard let companyId else { return }

        isSaving = true
        defer { isSaving = false }

        var params: [String: Any] = [
            "company_id": companyId,
            "name": derivedProjectName,
            "repo_path": repoPath.trimmingCharacters(in: .whitespacesAndNewlines),
            "status": selectedStatus,
        ]
        if !selectedGoalId.isEmpty {
            params["goal_id"] = selectedGoalId
        }
        if let targetDate {
            params["target_date"] = projectDialogTargetDateString(targetDate)
        }

        do {
            try await onCreate(params)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProjectDialogChip: View {
    let iconText: String?
    let text: String
    let textColor: Color

    init(iconText: String? = nil, text: String, textColor: Color) {
        self.iconText = iconText
        self.text = text
        self.textColor = textColor
    }

    var body: some View {
        HStack(spacing: iconText == nil ? 0 : 6) {
            if let iconText {
                Text(iconText)
                    .font(GeistFont.sans(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "B8B8B8"))
            }

            Text(text)
                .font(GeistFont.sans(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "050505"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "303030"), lineWidth: 1)
        )
    }
}

private struct CreateIssueSheet: View {
    @Environment(\.dismiss) private var dismiss

    let companyId: String?
    let agents: [DaemonAgent]
    let projects: [DaemonProject]
    let issues: [DaemonIssue]
    let onCreate: ([String: Any]) async throws -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var priority = "medium"
    @State private var selectedProjectId = ""
    @State private var selectedAssigneeAgentId = ""
    @State private var selectedParentIssueId = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Description", text: $description, axis: .vertical)
            Picker("Priority", selection: $priority) {
                Text("low").tag("low")
                Text("medium").tag("medium")
                Text("high").tag("high")
                Text("urgent").tag("urgent")
            }
            Picker("Project", selection: $selectedProjectId) {
                Text("None").tag("")
                ForEach(projects) { project in
                    Text(project.name).tag(project.id)
                }
            }
            Picker("Assignee", selection: $selectedAssigneeAgentId) {
                Text("None").tag("")
                ForEach(agents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }
            Picker("Parent Issue", selection: $selectedParentIssueId) {
                Text("None").tag("")
                ForEach(issues) { issue in
                    Text(issue.identifier ?? issue.title).tag(issue.id)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Issue") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || companyId == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.lg)
    }

    private func save() async {
        guard let companyId else { return }

        isSaving = true
        defer { isSaving = false }

        var params: [String: Any] = [
            "company_id": companyId,
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "priority": priority,
        ]
        if let description = description.nonEmpty { params["description"] = description }
        if !selectedProjectId.isEmpty { params["project_id"] = selectedProjectId }
        if !selectedAssigneeAgentId.isEmpty { params["assignee_agent_id"] = selectedAssigneeAgentId }
        if !selectedParentIssueId.isEmpty { params["parent_id"] = selectedParentIssueId }

        do {
            try await onCreate(params)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func formatDate(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Unknown" }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: value) {
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    return value
}

private func parsedDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func projectDialogStatusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "planned":
        return Color(hex: "6F6F6F")
    case "completed":
        return Color(hex: "B8B8B8")
    default:
        return Color(hex: "D8D8D8")
    }
}

private func projectDialogDateLabel(_ date: Date?) -> String {
    guard let date else { return "dd/mm/yyyy" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_GB")
    formatter.dateFormat = "dd/MM/yyyy"
    return formatter.string(from: date)
}

private func projectDialogTargetDateString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Calendar.current.startOfDay(for: date))
}

private func anyCodableDictionaryText(_ dictionary: [String: AnyCodableValue]) -> String {
    dictionary
        .sorted(by: { $0.key < $1.key })
        .map { key, value in
            "\(key): \(String(describing: value.value))"
        }
        .joined(separator: "\n")
}

private func sidebarOrderedAgents(_ agents: [DaemonAgent], ceoAgentId: String?) -> [DaemonAgent] {
    if let ceoAgentId,
       let ceoAgent = agents.first(where: { $0.id == ceoAgentId }) {
        return [ceoAgent] + agents.filter { $0.id != ceoAgentId }
    }

    if let ceoAgent = agents.first(where: { $0.role.caseInsensitiveCompare("ceo") == .orderedSame }) {
        return [ceoAgent] + agents.filter { $0.id != ceoAgent.id }
    }

    return agents
}

private func money(_ cents: Int) -> String {
    let dollars = Double(cents) / 100.0
    return dollars.formatted(.currency(code: "USD"))
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
