//
//  BoardRootView.swift
//  unbound-macos
//
//  Native macOS shell for the Unbound local workspace experience.
//

import AppKit
import Logging
import SwiftUI

private let boardLogger = Logger(label: "app.ui.board")

enum BoardRootLayout: Equatable {
    case workspace
    case settings
    case companyDashboard
}

private enum ConversationComposerMode {
    case conversation
    case queuedMessage

    var title: String {
        switch self {
        case .conversation:
            return "Create Conversation"
        case .queuedMessage:
            return "Queue Message"
        }
    }
}

func boardRootLayout(
    currentShell: BoardShellKind,
    selectedScreen: AppScreen
) -> BoardRootLayout {
    if currentShell == .workspace {
        return .workspace
    }

    if selectedScreen == .settings {
        return .settings
    }

    return .companyDashboard
}

struct BoardRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingCreateCompanySheet = false
    @State private var showingCreateIssueSheet = false
    @State private var showingCreateProjectDialog = false
    @State private var conversationComposerMode: ConversationComposerMode = .conversation
    @State private var conversationComposerProjectId = ""
    @State private var conversationComposerParentIssueId = ""

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var layout: BoardRootLayout {
        boardRootLayout(
            currentShell: appState.currentShell,
            selectedScreen: appState.selectedScreen
        )
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

            switch layout {
            case .workspace:
                BoardWorkspacesRoute()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .settings:
                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .companyDashboard:
                CompanyDashboardSidebar(
                    selectedCompany: appState.selectedCompany,
                    selectedScreen: appState.selectedScreen,
                    isLoading: appState.isLoadingBoardData,
                    boardError: appState.boardError,
                    onRefresh: {
                        Task {
                            await appState.refreshCompanies()
                            await appState.refreshCompanyScopedBoardData()
                        }
                    },
                    onSelectScreen: { screen in
                        if screen == .issues {
                            appState.showIssuesList()
                        } else {
                            appState.selectedScreen = screen
                        }
                    },
                    onShowCreateIssue: {
                        presentConversationComposer()
                    }
                )

                companyDashboardContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(colors.background)
        .sheet(isPresented: $showingCreateCompanySheet) {
            CreateCompanySheet(
                onCreate: { name, description, budget, color in
                    _ = try await appState.createCompany(
                        name: name,
                        description: description,
                        budgetMonthlyCents: budget,
                        brandColor: color
                    )
                }
            )
            .frame(width: 520, height: 420)
        }
        .sheet(isPresented: $showingCreateIssueSheet) {
            CreateIssueSheet(
                companyId: appState.selectedCompanyId,
                defaultExecutorId: appState.selectedCompany?.ceoAgentId ?? appState.agents.first?.id,
                projects: appState.projects,
                issues: appState.issues,
                mode: conversationComposerMode,
                defaultProjectId: conversationComposerProjectId.nonEmpty,
                defaultParentIssueId: conversationComposerParentIssueId.nonEmpty,
                onCreate: { params in
                    _ = try await appState.createIssue(params: params)
                }
            )
            .frame(width: 620, height: 700)
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
        .task {
            if appState.isDaemonConnected, !appState.hasCompletedInitialCompanyLoad {
                await appState.loadBoardDataAsync()
            }
        }
    }

    private func presentConversationComposer(
        mode: ConversationComposerMode = .conversation,
        projectId: String? = nil,
        parentIssueId: String? = nil
    ) {
        conversationComposerMode = mode
        conversationComposerProjectId = projectId ?? ""
        conversationComposerParentIssueId = parentIssueId ?? ""
        showingCreateIssueSheet = true
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
        case .agents, .issues, .approvals:
            IssuesRoute(onQueueMessage: { issue in
                presentConversationComposer(
                    mode: .queuedMessage,
                    projectId: issue.projectId,
                    parentIssueId: issue.id
                )
            })
        case .projects:
            ProjectsRoute(onShowCreateProject: { showingCreateProjectDialog = true })
        case .goals:
            BoardPlaceholderRoute(
                title: "Goals",
                message: "The schema is in place. Goal service and UI parity are the next daemon port."
            )
        case .activity:
            ActivityRoute()
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
                    .help("Create space")
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
    let selectedScreen: AppScreen
    let isLoading: Bool
    let boardError: String?
    let onRefresh: () -> Void
    let onSelectScreen: (AppScreen) -> Void
    let onShowCreateIssue: () -> Void

    private let primarySections: [(String, [AppScreen])] = [
        ("Core", [.issues, .workspaces, .projects]),
    ]

    private let companySection: (String, [AppScreen]) = ("Spaces", [.activity, .settings])

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedCompany?.name ?? "Space")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color(hex: "F5F5F5"))
                        .lineLimit(1)

                    Text(selectedCompany?.issuePrefix ?? "Local model workspace")
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
                            title: "New Conversation",
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

    private var visibleConversations: [DaemonIssue] {
        appState.issues.filter { issue in
            issue.hiddenAt == nil && isRootConversationIssue(issue)
        }
    }

    private var openConversationCount: Int {
        visibleConversations.filter { $0.completedAt == nil && $0.cancelledAt == nil }.count
    }

    private var recentConversations: [DaemonIssue] {
        visibleConversations.sorted {
            (parsedDate($0.updatedAt) ?? .distantPast) > (parsedDate($1.updatedAt) ?? .distantPast)
        }
    }

    private var configuredModelCounts: [(label: String, count: Int)] {
        Dictionary(grouping: visibleConversations) {
            issueModelLabel($0, agents: appState.agents)
        }
        .map { (label: $0.key, count: $0.value.count) }
        .sorted {
            if $0.count == $1.count {
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
            return $0.count > $1.count
        }
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
                        DashboardMetricCard(title: "Conversation Prefix", value: company.issuePrefix, footnote: "Next #\(company.issueCounter + 1)")
                        DashboardMetricCard(title: "Open Conversations", value: "\(openConversationCount)", footnote: "\(visibleConversations.count) total")
                        DashboardMetricCard(
                            title: "Configured Models",
                            value: "\(configuredModelCounts.count)",
                            footnote: configuredModelCounts.first.map { "\($0.label) leads" } ?? "Defaults apply per conversation"
                        )
                        DashboardMetricCard(title: "Live Workspaces", value: "\(appState.workspaces.count)", footnote: appState.workspaces.isEmpty ? "No active coding sessions" : "Conversation-owned only")
                        DashboardMetricCard(title: "Projects", value: "\(appState.projects.count)", footnote: "Main repo anchors")
                        DashboardMetricCard(title: "Monthly Budget", value: money(company.budgetMonthlyCents), footnote: "Spent \(money(company.spentMonthlyCents))")
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Spacing.md)], spacing: Spacing.md) {
                        DashboardSurfaceCard(title: "Models") {
                            if configuredModelCounts.isEmpty {
                                DashboardEmptyText("Conversations choose Claude or Codex directly. Model routing will show up here once work is created.")
                            } else {
                                ForEach(Array(configuredModelCounts.prefix(5)), id: \.label) { item in
                                    DashboardLineItem(
                                        title: item.label,
                                        subtitle: item.count == 1 ? "1 conversation" : "\(item.count) conversations",
                                        trailing: item.count == 1 ? "active" : "configured"
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

                    DashboardSurfaceCard(title: "Recent Conversations") {
                        if recentConversations.isEmpty {
                            DashboardEmptyText("Conversations drive workspaces. Create one to start model work.")
                        } else {
                            ForEach(recentConversations.prefix(8)) { issue in
                                Button {
                                    appState.showIssueDetail(issueId: issue.id)
                                } label: {
                                    DashboardLineItem(
                                        title: issue.identifier ?? issue.title,
                                        subtitle: [issue.title, issueModelLabel(issue, agents: appState.agents)]
                                            .joined(separator: " · "),
                                        trailing: issue.workspaceSessionId == nil ? issue.status : "workspace"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    DashboardSurfaceCard(title: "Active Workspaces") {
                        if appState.workspaces.isEmpty {
                            DashboardEmptyText("Conversation workspaces appear here once a model starts working.")
                        } else {
                            ForEach(appState.workspaces.prefix(6)) { workspace in
                                Button {
                                    appState.selectedBoardWorkspaceId = workspace.id
                                    appState.selectedScreen = .workspaces
                                } label: {
                                    DashboardLineItem(
                                        title: workspace.issueIdentifier ?? workspace.title,
                                        subtitle: [
                                            workspace.issueTitle,
                                            workspace.projectName,
                                            workspaceModelLabel(workspace, issues: appState.issues, agents: appState.agents)
                                        ]
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
                    title: "Select a space",
                    message: "Choose a space from the rail to view its dashboard."
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

    private var issueActivityFeedItems: [InboxFeedItem] {
        visibleIssues.flatMap { issue in
            var items: [InboxFeedItem] = []
            let issueTitle = issue.identifier ?? issue.title

            if let comments = appState.issueComments[issue.id] {
                items.append(contentsOf: comments.map { comment in
                    InboxFeedItem(
                        id: "comment-\(comment.id)",
                        timestamp: parsedDate(comment.createdAt) ?? .distantPast,
                        title: issueCommentAuthorLabel(appState.agents, comment: comment),
                        subtitle: "\(issueTitle) · \(comment.body)",
                        trailingLabel: "message",
                        issueId: issue.id
                    )
                })
            }

            items.append(
                InboxFeedItem(
                    id: "issue-update-\(issue.id)",
                    timestamp: parsedDate(issue.updatedAt) ?? .distantPast,
                    title: issueTitle,
                    subtitle: "\(formatDate(issue.updatedAt)) · \(conversationActivitySummary(issue))",
                    trailingLabel: issue.status,
                    issueId: issue.id
                )
            )

            return items
        }
    }

    private var feedItems: [InboxFeedItem] {
        Array(issueActivityFeedItems.sorted { $0.timestamp > $1.timestamp }.prefix(50))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Inbox")
                        .font(Typography.caption)
                        .foregroundStyle(colors.primary)
                    Text("Recent conversation activity")
                        .font(Typography.pageTitle)
                }

                DashboardSurfaceCard(title: "Inbox") {
                    if feedItems.isEmpty {
                        DashboardEmptyText("Recent conversation updates and queued follow-ups will appear here.")
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
        appState.showIssueDetail(issueId: item.issueId)
    }

}

private struct ActivityRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var visibleIssues: [DaemonIssue] {
        appState.issues.filter { $0.hiddenAt == nil }
    }

    private var visibleIssueIdsKey: String {
        visibleIssues.map(\.id).sorted().joined(separator: "|")
    }

    private var feedItems: [InboxFeedItem] {
        visibleIssues
            .flatMap { issue in
                let issueTitle = issue.identifier ?? issue.title
                let comments = appState.issueComments[issue.id] ?? []
                return comments.map { comment in
                    InboxFeedItem(
                        id: "message-\(comment.id)",
                        timestamp: parsedDate(comment.createdAt) ?? .distantPast,
                        title: issueCommentAuthorLabel(appState.agents, comment: comment),
                        subtitle: "\(issueTitle) · \(comment.body)",
                        trailingLabel: "message",
                        issueId: issue.id
                    )
                }
            }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(50)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Activity")
                        .font(Typography.caption)
                        .foregroundStyle(colors.primary)
                    Text("Model messages across conversations")
                        .font(Typography.pageTitle)
                }

                DashboardSurfaceCard(title: "Recent Activity") {
                    if feedItems.isEmpty {
                        DashboardEmptyText("Model messages across conversations will appear here.")
                    } else {
                        ForEach(feedItems) { item in
                            Button {
                                appState.showIssueDetail(issueId: item.issueId)
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
        .task(id: visibleIssueIdsKey) {
            for issue in visibleIssues where appState.issueComments[issue.id] == nil {
                await appState.refreshIssueComments(issueId: issue.id)
            }
        }
    }
}

private struct InboxFeedItem: Identifiable {
    let id: String
    let timestamp: Date
    let title: String
    let subtitle: String
    let trailingLabel: String
    let issueId: String
}

struct CreateFirstCompanyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = ""
    @State private var description = ""
    @State private var budget = ""
    @State private var brandColor = "#0F766E"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !isSaving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        BoardOnboardingContainer(
            eyebrow: "Space setup",
            title: "Set up your first space",
            message: "Your device is ready. Create a space and Unbound will prepare its default local executor automatically so projects and conversations can start immediately."
        ) {
            BoardCardSurface(padding: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Space details")
                        .font(Typography.h3)

                    Text("This creates the space shell and prepares its default local executor in the background.")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                BoardFormFieldGroup(
                    label: "Space Name",
                    hint: "Shown in the spaces rail, sidebar, and dashboard."
                ) {
                    ShadcnTextField("Acme Systems", text: $name, variant: .filled)
                }

                BoardFormFieldGroup(
                    label: "Description",
                    hint: "Optional context for what this space does or what the board is managing."
                ) {
                    BoardMultilineInput(
                        placeholder: "Internal tools, customer support operations, product engineering, or another operating context...",
                        text: $description
                    )
                }

                BoardFormFieldGroup(
                    label: "Monthly Budget (cents)",
                    hint: "Stored as an integer so the board can track budget and spend without currency rounding."
                ) {
                    ShadcnTextField("500000", text: $budget, variant: .filled)
                }

                BoardFormFieldGroup(
                    label: "Brand Color",
                    hint: "Optional hex color used for the space badge and accents in the board."
                ) {
                    ShadcnTextField("#0F766E", text: $brandColor, variant: .filled)
                }

                if let errorMessage {
                    BoardInlineMessage(text: errorMessage, tone: .error)
                }

                HStack {
                    Spacer()

                    Button {
                        Task { await save() }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Create Space")
                                .fontWeight(.medium)
                        }
                    }
                    .buttonPrimary(size: .md)
                    .disabled(!canCreate)
                }
            }
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
                brandColor: brandColor.nonEmpty
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BoardOnboardingStepIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    let step: BoardOnboardingStep

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            indicator(number: 1, title: "CEO", isActive: step == .createCEO, isComplete: step == .bootstrapIssue)
            indicator(number: 2, title: "Bootstrap Conversation", isActive: step == .bootstrapIssue, isComplete: false)
        }
    }

    @ViewBuilder
    private func indicator(number: Int, title: String, isActive: Bool, isComplete: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(isActive || isComplete ? colors.primary : colors.input)
                    .frame(width: 24, height: 24)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(colors.primaryForeground)
                } else {
                    Text("\(number)")
                        .font(Typography.captionMedium)
                        .foregroundStyle(isActive ? colors.primaryForeground : colors.mutedForeground)
                }
            }

            Text(title)
                .font(Typography.captionMedium)
                .foregroundStyle(isActive || isComplete ? colors.foreground : colors.mutedForeground)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background((isActive || isComplete ? colors.accent : colors.input.opacity(0.7)))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isActive || isComplete ? colors.primary.opacity(0.24) : colors.border, lineWidth: BorderWidth.default)
        )
    }
}

struct CreateCEOAgentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = "CEO"
    @State private var title = "Chief Executive Officer"
    @State private var bootstrapIssueTitle = BoardOnboardingState.initial(companyId: "preview").bootstrapIssueTitle
    @State private var bootstrapIssueDescription = BoardOnboardingState.initial(companyId: "preview").bootstrapIssueDescription
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var currentStep: BoardOnboardingStep {
        appState.boardOnboardingState?.step
            ?? (appState.selectedCompany?.ceoAgentId == nil ? .createCEO : .bootstrapIssue)
    }

    private var companyName: String {
        appState.selectedCompany?.name ?? "this space"
    }

    private var resolvedCEOAgentId: String? {
        appState.boardOnboardingState?.ceoAgentId ?? appState.selectedCompany?.ceoAgentId
    }

    private var createdCEOAgent: DaemonAgent? {
        guard let resolvedCEOAgentId else { return nil }
        return appState.agents.first(where: { $0.id == resolvedCEOAgentId })
    }

    private var canCreateCEO: Bool {
        !isSaving
            && appState.selectedCompanyId != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCreateBootstrapIssue: Bool {
        !isSaving
            && appState.selectedCompanyId != nil
            && resolvedCEOAgentId != nil
            && !bootstrapIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bootstrapIssueDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        BoardOnboardingContainer(
            eyebrow: "CEO setup required",
            title: currentStep == .createCEO ? "Create the CEO agent" : "Create the CEO bootstrap conversation",
            message: currentStep == .createCEO
                ? "\(companyName) exists, but the board stays locked until it has a CEO. Step one creates the CEO agent with the local runtime defaults that power its first run."
                : "\(companyName) now has a CEO, but the space is still blocked until you create the bootstrap conversation that becomes the CEO’s first assigned run."
        ) {
            BoardCardSurface(padding: Spacing.xl) {
                BoardOnboardingStepIndicator(step: currentStep)

                if currentStep == .createCEO {
                    ceoConfigurationStep
                } else {
                    bootstrapIssueStep
                }
            }
        }
        .task(id: appState.selectedCompanyId) {
            appState.ensureBoardOnboardingStateForSelectedCompany()
            syncDraftsFromOnboardingState()
        }
        .onChange(of: name) { _, newValue in
            appState.updateBoardOnboardingDraft(ceoName: newValue)
        }
        .onChange(of: title) { _, newValue in
            appState.updateBoardOnboardingDraft(ceoTitle: newValue)
        }
        .onChange(of: bootstrapIssueTitle) { _, newValue in
            appState.updateBoardOnboardingDraft(bootstrapIssueTitle: newValue)
        }
        .onChange(of: bootstrapIssueDescription) { _, newValue in
            appState.updateBoardOnboardingDraft(bootstrapIssueDescription: newValue)
        }
    }

    @ViewBuilder
    private var ceoConfigurationStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Step 1 of 2")
                .font(Typography.caption)
                .foregroundStyle(colors.primary)

            Text("Create the space’s CEO")
                .font(Typography.h3)

            Text("This creates the CEO agent record, reserves the local home path, and applies the default heartbeat runtime. The bootstrap conversation in the next step is what actually initializes the agent’s instructions and operating files.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }

        BoardInlineMessage(
            text: "Execution uses the local Claude Code runtime on this device. Heartbeat is enabled, on-demand wakeups stay on, the run interval is one hour, and the CEO executes one run at a time.",
            tone: .info
        )

        BoardFormFieldGroup(
            label: "Agent Name",
            hint: "Shown across the board as the space’s executive owner."
        ) {
            ShadcnTextField("CEO", text: $name, variant: .filled)
        }

        BoardFormFieldGroup(
            label: "Title",
            hint: "Defaults to the executive title used in space dashboards and run details."
        ) {
            ShadcnTextField("Chief Executive Officer", text: $title, variant: .filled)
        }

        BoardInlineMessage(
            text: "The CEO uses the `crown` icon, becomes the space’s root reporting node, and stays in onboarding until the bootstrap conversation is created.",
            tone: .info
        )

        if let errorMessage {
            BoardInlineMessage(text: errorMessage, tone: .error)
        }

        HStack {
            Spacer()

            Button {
                Task { await createCEOAndContinue() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Create CEO and Continue")
                        .fontWeight(.medium)
                }
            }
            .buttonPrimary(size: .md)
            .disabled(!canCreateCEO)
        }
    }

    @ViewBuilder
    private var bootstrapIssueStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Step 2 of 2")
                .font(Typography.caption)
                .foregroundStyle(colors.primary)

            Text("Create the CEO bootstrap conversation")
                .font(Typography.h3)

            Text("This conversation is mandatory. As soon as you create it, Unbound assigns it to the CEO and the existing assignment trigger queues the CEO’s first run automatically.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let createdCEOAgent {
            BoardCardSurface(padding: Spacing.lg, elevation: Elevation.sm) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: IconSize.lg, weight: .semibold))
                        .foregroundStyle(colors.primary)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(createdCEOAgent.name)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(colors.foreground)

                        Text(createdCEOAgent.title ?? "Chief Executive Officer")
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)

                        if let homePath = createdCEOAgent.homePath {
                            Text(homePath)
                                .font(Typography.micro)
                                .foregroundStyle(colors.mutedForeground)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                }
            }
        }

        BoardInlineMessage(
            text: "Use this conversation to tell the CEO how to create or fetch its own instruction set. The run prompt also includes the board helper commands the CEO must use for governed hires, conversation updates, and messages.",
            tone: .info
        )

        BoardFormFieldGroup(
            label: "Conversation Title",
            hint: "Paperclip uses a direct setup task here so the CEO’s first run is intentional and editable."
        ) {
            ShadcnTextField("Create your CEO HEARTBEAT.md", text: $bootstrapIssueTitle, variant: .filled)
        }

        BoardFormFieldGroup(
            label: "Bootstrap Brief",
            hint: "This becomes the first assigned task description for the CEO. Keep it editable so you can tune the bootstrap behavior and the first governed hire request."
        ) {
            BoardMultilineInput(
                placeholder: "Tell the CEO how to create its own instructions, initialize its local home, and what to do after bootstrap...",
                text: $bootstrapIssueDescription,
                minHeight: 180
            )
        }

        if let errorMessage {
            BoardInlineMessage(text: errorMessage, tone: .error)
        }

        HStack {
            Spacer()

            Button {
                Task { await createBootstrapIssue() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Create Bootstrap Conversation")
                        .fontWeight(.medium)
                }
            }
            .buttonPrimary(size: .md)
            .disabled(!canCreateBootstrapIssue)
        }
    }

    private func createCEOAndContinue() async {
        guard let companyId = appState.selectedCompanyId else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.updateBoardOnboardingDraft(
            ceoName: trimmedName,
            ceoTitle: trimmedTitle,
            bootstrapIssueTitle: bootstrapIssueTitle,
            bootstrapIssueDescription: bootstrapIssueDescription
        )

        do {
            let params: [String: Any] = [
                "company_id": companyId,
                "name": trimmedName,
                "role": "ceo",
                "title": trimmedTitle,
                "icon": "crown",
                "adapter_type": "process",
                "runtime_config": [
                    "heartbeat": [
                        "enabled": true,
                        "intervalSec": 3600,
                        "wakeOnDemand": true,
                        "cooldownSec": 10,
                        "maxConcurrentRuns": 1,
                    ],
                ],
            ]
            let agent = try await appState.createAgent(params: params)
            appState.advanceBoardOnboardingToBootstrapIssue(ceoAgentId: agent.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createBootstrapIssue() async {
        guard let companyId = appState.selectedCompanyId else { return }
        guard let resolvedCEOAgentId else {
            errorMessage = "The CEO agent is missing. Recreate the CEO step before creating the bootstrap conversation."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedIssueTitle = bootstrapIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIssueDescription = bootstrapIssueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.updateBoardOnboardingDraft(
            ceoName: name,
            ceoTitle: title,
            bootstrapIssueTitle: trimmedIssueTitle,
            bootstrapIssueDescription: trimmedIssueDescription
        )

        do {
            var issue = try await appState.createIssue(
                params: [
                    "company_id": companyId,
                    "title": trimmedIssueTitle,
                    "description": trimmedIssueDescription,
                    "priority": "high",
                    "assignee_agent_id": resolvedCEOAgentId,
                ]
            )
            if issue.assigneeAgentId != resolvedCEOAgentId {
                issue = try await appState.updateIssue(
                    params: [
                        "issue_id": issue.id,
                        "assignee_agent_id": resolvedCEOAgentId,
                    ]
                )
            }
            appState.clearBoardOnboardingState()
            appState.showIssueDetail(issueId: issue.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncDraftsFromOnboardingState() {
        if let onboardingState = appState.boardOnboardingState {
            name = onboardingState.ceoName
            title = onboardingState.ceoTitle
            bootstrapIssueTitle = onboardingState.bootstrapIssueTitle
            bootstrapIssueDescription = onboardingState.bootstrapIssueDescription
            return
        }

        if let selectedCompany = appState.selectedCompany {
            let defaults = BoardOnboardingState.initial(companyId: selectedCompany.id, companyName: selectedCompany.name)
            name = defaults.ceoName
            title = defaults.ceoTitle
            bootstrapIssueTitle = defaults.bootstrapIssueTitle
            bootstrapIssueDescription = defaults.bootstrapIssueDescription
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
        BoardOnboardingContainer(
            eyebrow: "Board unavailable",
            title: "Unable to load spaces",
            message: "Unbound could not finish loading the local board state. Retry once the daemon is healthy again."
        ) {
            BoardCardSurface(padding: Spacing.xl) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: IconSize.xxl))
                        .foregroundStyle(colors.destructive)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("The initial space check failed")
                            .font(Typography.h4)
                            .foregroundStyle(colors.foreground)

                        Text("The board stays unavailable until this local load completes successfully.")
                            .font(Typography.bodySmall)
                            .foregroundStyle(colors.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                BoardInlineMessage(text: message, tone: .error)

                HStack {
                    Spacer()
                    Button("Retry", action: onRetry)
                        .buttonPrimary(size: .md)
                }
            }
        }
    }
}

private enum AgentRoutePage {
    case details
    case runs
}

private struct AgentsRoute: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var page: AgentRoutePage = .details
    @State private var agentRuns: [DaemonAgentRun] = []
    @State private var selectedRunId: String?
    @State private var selectedRun: DaemonAgentRun?
    @State private var runEvents: [DaemonAgentRunEvent] = []
    @State private var runLogContent = ""
    @State private var runLogOffset: UInt64 = 0
    @State private var isLoadingRuns = false
    @State private var isLoadingRunDetail = false
    @State private var isPerformingRunAction = false
    @State private var runError: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var orderedAgents: [DaemonAgent] {
        sidebarOrderedAgents(appState.agents, ceoAgentId: appState.selectedCompany?.ceoAgentId)
    }

    private var selectedAgent: DaemonAgent? {
        appState.selectedAgent ?? orderedAgents.first
    }

    private var selectedRunIsLive: Bool {
        guard let selectedRun else { return false }
        return selectedRun.status == "queued" || selectedRun.status == "running"
    }

    private var pollKey: String {
        [
            selectedAgent?.id ?? "none",
            selectedRunId ?? "none",
            page == .runs ? "runs" : "details",
        ].joined(separator: ":")
    }

    var body: some View {
        Group {
            if page == .details {
                agentDetailsPage
            } else {
                agentRunsPage
            }
        }
        .background(colors.background)
        .task(id: appState.selectedCompanyId) {
            await handleAgentSelectionChange()
        }
        .task(id: appState.selectedAgentId) {
            await handleAgentSelectionChange()
        }
        .task(id: page) {
            if page == .runs {
                await loadRuns(resetSelection: true)
            }
        }
        .task(id: selectedRunId) {
            if page == .runs {
                await refreshSelectedRun(resetStreams: true)
            }
        }
        .task(id: pollKey) {
            await pollSelectedRunIfNeeded()
        }
    }

    private var agentDetailsPage: some View {
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
                            VStack(alignment: .trailing, spacing: Spacing.sm) {
                                StatusPill(text: agent.status)
                                Button {
                                    page = .runs
                                } label: {
                                    Label("View Runs", systemImage: "clock.arrow.circlepath")
                                }
                                .buttonStyle(.bordered)
                            }
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
                    title: "No agents in this space",
                    message: "Agents will appear here after the CEO creates them."
                )
            }
        }
    }

    private var agentRunsPage: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Agent Runs")
                        .font(Typography.caption)
                        .foregroundStyle(colors.primary)
                    Text(selectedAgent.map { "\($0.name) Run History" } ?? "Run History")
                        .font(Typography.pageTitle)
                }

                Spacer()

                HStack(spacing: Spacing.sm) {
                    if isLoadingRuns || isLoadingRunDetail {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(hex: "F59E0B"))
                    }

                    Button {
                        Task {
                            await loadRuns(resetSelection: false)
                            await refreshSelectedRun(resetStreams: true)
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        page = .details
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            ShadcnDivider()

            if selectedAgent == nil {
                BoardEmptyState(
                    title: "Select an agent",
                    message: "Runs appear once an agent is selected."
                )
            } else {
                HSplitView {
                    runsListPane
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

                    runsDetailPane
                        .frame(minWidth: 460, idealWidth: 860, maxWidth: .infinity)
                }
            }
        }
    }

    private var runsListPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let runError {
                    Text(runError)
                        .font(Typography.caption)
                        .foregroundStyle(Color.red)
                }

                if agentRuns.isEmpty && !isLoadingRuns {
                    BoardEmptyState(
                        title: "No runs yet",
                        message: "Queued, running, and completed agent runs will appear here."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ForEach(agentRuns) { run in
                        AgentRunListRow(
                            run: run,
                            isSelected: selectedRunId == run.id,
                            action: {
                                selectedRunId = run.id
                            }
                        )
                    }
                }
            }
            .padding(Spacing.lg)
        }
        .background(colors.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(hex: "1F1F1F"))
                .frame(width: BorderWidth.default)
        }
    }

    private var runsDetailPane: some View {
        ScrollView {
            if let run = selectedRun {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(shortRunTitle(run.id))
                                .font(Typography.caption)
                                .foregroundStyle(colors.primary)
                            Text(agentRunSummary(run))
                                .font(Typography.h3)
                                .foregroundStyle(Color(hex: "F5F5F5"))
                            Text("\(agentRunInvocationSourceLabel(run.invocationSource)) · \(formatRelativeDate(run.createdAt))")
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                        }
                        Spacer()
                        HStack(spacing: Spacing.sm) {
                            if run.status == "queued" || run.status == "running" {
                                Button {
                                    Task {
                                        await performRunAction {
                                            try await appState.daemonClient.cancelAgentRun(runId: run.id)
                                        }
                                    }
                                } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isPerformingRunAction)
                            }

                            if run.status == "failed" || run.status == "timed_out" {
                                Button {
                                    Task {
                                        await performRunAction {
                                            try await appState.daemonClient.retryAgentRun(runId: run.id)
                                        }
                                    }
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isPerformingRunAction)
                            }

                            if run.status == "failed", run.errorCode == "process_lost" {
                                Button {
                                    Task {
                                        await performRunAction {
                                            try await appState.daemonClient.resumeAgentRun(runId: run.id)
                                        }
                                    }
                                } label: {
                                    Label("Resume", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isPerformingRunAction)
                            }

                            StatusPill(text: agentRunStatusLabel(run.status))
                        }
                    }

                    DashboardSurfaceCard(title: "Summary") {
                        DetailGrid(items: [
                            ("Status", agentRunStatusLabel(run.status)),
                            ("Invocation Source", agentRunInvocationSourceLabel(run.invocationSource)),
                            ("Trigger Detail", agentRunTriggerDetailLabel(run.triggerDetail)),
                            ("Wake Reason", agentRunWakeReasonLabel(run.wakeReason)),
                            ("Started", formatDate(run.startedAt)),
                            ("Finished", formatDate(run.finishedAt)),
                            ("Exit Code", run.exitCode.map(String.init) ?? "None"),
                            ("Signal", run.signal ?? "None"),
                            ("Session Before", run.sessionIdBefore ?? "None"),
                            ("Session After", run.sessionIdAfter ?? "None"),
                            ("Log Bytes", run.logBytes.map(String.init) ?? "0"),
                            ("Created", formatDate(run.createdAt))
                        ])
                    }

                    if let error = run.error, !error.isEmpty {
                        DashboardSurfaceCard(title: "Error") {
                            Text(error)
                                .font(Typography.body)
                                .foregroundStyle(Color(hex: "F5F5F5"))
                                .textSelection(.enabled)
                        }
                    }

                    DashboardSurfaceCard(title: "Excerpts") {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            if let stdoutExcerpt = run.stdoutExcerpt, !stdoutExcerpt.isEmpty {
                                DetailSection(title: "Stdout", text: stdoutExcerpt)
                            }
                            if let stderrExcerpt = run.stderrExcerpt, !stderrExcerpt.isEmpty {
                                DetailSection(title: "Stderr", text: stderrExcerpt)
                            }
                            if run.stdoutExcerpt == nil, run.stderrExcerpt == nil {
                                DashboardEmptyText("Run excerpts appear as output is captured.")
                            }
                        }
                    }

                    if run.usageJson != nil || run.resultJson != nil || run.contextSnapshot != nil {
                        DashboardSurfaceCard(title: "Payloads") {
                            VStack(alignment: .leading, spacing: Spacing.lg) {
                                if let usage = run.usageJson {
                                    AgentRunCodePanel(
                                        title: "Usage",
                                        text: RunJSONFormatter.format(usage),
                                        maxHeight: 240
                                    )
                                }
                                if let result = run.resultJson {
                                    AgentRunCodePanel(
                                        title: "Result",
                                        text: RunJSONFormatter.format(result),
                                        maxHeight: 240
                                    )
                                }
                                if let snapshot = run.contextSnapshot {
                                    AgentRunCodePanel(
                                        title: "Context Snapshot",
                                        text: RunJSONFormatter.format(snapshot),
                                        maxHeight: 240
                                    )
                                }
                            }
                        }
                    }

                    DashboardSurfaceCard(title: "Event Stream") {
                        if runEvents.isEmpty {
                            DashboardEmptyText("Structured run events will appear here.")
                        } else {
                            ForEach(runEvents) { event in
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    HStack {
                                        Text("#\(event.seq) \(agentRunEventLabel(event.eventType))")
                                            .font(Typography.bodyMedium)
                                            .foregroundStyle(Color(hex: "F5F5F5"))
                                        Spacer()
                                        Text(formatDate(event.createdAt))
                                            .font(Typography.micro)
                                            .foregroundStyle(colors.mutedForeground)
                                    }
                                    Text([
                                        event.stream,
                                        event.level,
                                        event.message,
                                    ].compactMap { $0 }.joined(separator: " · "))
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.mutedForeground)
                                    if let payload = event.payload {
                                        AgentRunCodePanel(
                                            title: "Payload",
                                            text: RunJSONFormatter.format(payload),
                                            maxHeight: 180
                                        )
                                        .padding(.top, Spacing.xs)
                                    }
                                }
                                .padding(.vertical, Spacing.xxs)
                            }
                        }
                    }

                    DashboardSurfaceCard(title: "Log") {
                        if runLogContent.isEmpty {
                            DashboardEmptyText("Live NDJSON log output will appear here.")
                        } else {
                            AgentRunCodePanel(
                                title: "Raw NDJSON Log",
                                text: RunJSONFormatter.rawText(runLogContent),
                                language: "json",
                                badgeText: "NDJSON",
                                maxHeight: 360
                            )
                        }
                    }
                }
                .padding(Spacing.xl)
            } else {
                BoardEmptyState(
                    title: "Select a run",
                    message: "Choose a run from the list to inspect its details, logs, and event stream."
                )
            }
        }
        .background(colors.background)
    }

    @MainActor
    private func handleAgentSelectionChange() async {
        ensureSelectedAgentIfNeeded()
        agentRuns = []
        selectedRun = nil
        selectedRunId = nil
        runEvents = []
        runLogContent = ""
        runLogOffset = 0
        runError = nil

        if page == .runs {
            await loadRuns(resetSelection: true)
        }
    }

    @MainActor
    private func ensureSelectedAgentIfNeeded() {
        guard appState.selectedAgentId == nil || appState.selectedAgent == nil else { return }
        appState.selectedAgentId = orderedAgents.first?.id
    }

    @MainActor
    private func loadRuns(resetSelection: Bool) async {
        guard let agent = selectedAgent else {
            agentRuns = []
            selectedRun = nil
            selectedRunId = nil
            return
        }

        isLoadingRuns = true
        defer { isLoadingRuns = false }

        do {
            let runs = try await appState.daemonClient.listAgentRuns(agentId: agent.id, limit: 200)
            agentRuns = runs
            runError = nil

            if resetSelection || selectedRunId == nil || !runs.contains(where: { $0.id == selectedRunId }) {
                selectedRunId = runs.first?.id
            }
            if let selectedRunId,
               let current = runs.first(where: { $0.id == selectedRunId }) {
                selectedRun = current
            }
        } catch {
            runError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshSelectedRun(resetStreams: Bool) async {
        guard page == .runs, let runId = selectedRunId else { return }

        isLoadingRunDetail = true
        defer { isLoadingRunDetail = false }

        do {
            let run = try await appState.daemonClient.getAgentRun(runId: runId)
            let afterSeq = resetStreams ? nil : runEvents.last?.seq
            let events = try await appState.daemonClient.listAgentRunEvents(
                runId: runId,
                afterSeq: afterSeq,
                limit: 400
            )
            let logChunk = try await appState.daemonClient.readAgentRunLog(
                runId: runId,
                offset: resetStreams ? 0 : runLogOffset
            )

            selectedRun = run
            if let index = agentRuns.firstIndex(where: { $0.id == run.id }) {
                agentRuns[index] = run
            }

            if resetStreams {
                runEvents = events
                runLogContent = logChunk.content
            } else {
                runEvents.append(contentsOf: events)
                if !logChunk.content.isEmpty {
                    runLogContent += logChunk.content
                }
            }
            runLogOffset = logChunk.nextOffset
            runError = nil
        } catch {
            runError = error.localizedDescription
        }
    }

    @MainActor
    private func pollSelectedRunIfNeeded() async {
        guard page == .runs else { return }

        while !Task.isCancelled {
            guard selectedRunIsLive else { break }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { break }
            await loadRuns(resetSelection: false)
            await refreshSelectedRun(resetStreams: false)
        }
    }

    @MainActor
    private func performRunAction(
        operation: @escaping () async throws -> DaemonAgentRun
    ) async {
        isPerformingRunAction = true
        defer { isPerformingRunAction = false }

        do {
            let updatedRun = try await operation()
            runError = nil
            await loadRuns(resetSelection: false)
            selectedRunId = updatedRun.id
            await refreshSelectedRun(resetStreams: true)
        } catch {
            runError = error.localizedDescription
        }
    }
}

private struct AgentRunListRow: View {
    let run: DaemonAgentRun
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(shortRunTitle(run.id))
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color(hex: "F5F5F5"))
                        Text(agentRunSummary(run))
                            .font(Typography.caption)
                            .foregroundStyle(Color(hex: "9A9A9A"))
                            .lineLimit(2)
                    }
                    Spacer()
                    StatusPill(text: agentRunStatusLabel(run.status))
                }

                HStack(spacing: Spacing.sm) {
                    Text(agentRunInvocationSourceLabel(run.invocationSource))
                        .font(Typography.micro)
                        .foregroundStyle(Color(hex: "F59E0B"))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color(hex: "1B1407"))
                        .clipShape(Capsule())
                    Text(formatRelativeDate(run.createdAt))
                        .font(Typography.micro)
                        .foregroundStyle(Color(hex: "7A7A7A"))
                    Spacer()
                    if let wakeReason = run.wakeReason {
                        Text(agentRunWakeReasonLabel(Optional(wakeReason)))
                            .font(Typography.micro)
                            .foregroundStyle(Color(hex: "7A7A7A"))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color(hex: "181818") : Color(hex: "101010"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color(hex: "2E2E2E") : Color(hex: "191919"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private enum ConversationRuntimeProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }

    var command: String { rawValue }

    var defaultModelOptions: [String] {
        switch self {
        case .claude:
            return ["default"] + AIModel.allModels.compactMap(\.modelIdentifier)
        case .codex:
            return ["default", "gpt-5", "gpt-5-mini", "gpt-5-codex"]
        }
    }

    var browserLabel: String {
        switch self {
        case .claude:
            return "Enable Chrome"
        case .codex:
            return "Enable web search"
        }
    }

    var browserHint: String {
        switch self {
        case .claude:
            return "Allow browser automation inside Claude runs."
        case .codex:
            return "Expose Codex web search during runs."
        }
    }
}

private struct IssueRuntimeDraft {
    static let thinkingEffortOptions = ["auto", "low", "medium", "high"]

    var provider: ConversationRuntimeProvider = .claude
    var model: String = "default"
    var thinkingEffort: String = "auto"
    var planMode = false
    var enableChrome = false
    var skipPermissions = false

    init() {}

    init(issue: DaemonIssue) {
        let command = anyCodableString(issue.assigneeAdapterOverrides, key: "command") ?? "claude"
        let model = anyCodableString(issue.assigneeAdapterOverrides, key: "model") ?? "default"
        let provider = runtimeProvider(command: command, model: model)
        self.provider = provider
        self.model = model
        self.thinkingEffort =
            anyCodableString(issue.assigneeAdapterOverrides, key: "thinkingEffort")
            ?? anyCodableString(issue.assigneeAdapterOverrides, key: "reasoningEffort")
            ?? "auto"
        self.planMode = provider == .claude
            && anyCodableString(issue.assigneeAdapterOverrides, key: "permissionMode") == "plan"
        self.enableChrome = anyCodableBool(issue.assigneeAdapterOverrides, key: "enableChrome")
        self.skipPermissions = anyCodableBool(issue.assigneeAdapterOverrides, key: "skipPermissions")
    }

    func asAdapterOverrides() -> [String: Any] {
        [
            "command": provider.command,
            "model": model,
            "thinkingEffort": thinkingEffort,
            "reasoningEffort": thinkingEffort,
            "permissionMode": provider == .claude && planMode ? "plan" : "default",
            "planMode": provider == .claude && planMode,
            "enableChrome": enableChrome,
            "skipPermissions": skipPermissions,
        ]
    }
}

private struct IssueEditDraft {
    var title: String = ""
    var description: String = ""
    var status: String = "backlog"
    var projectId: String = ""
    var parentId: String = ""
    var runtime = IssueRuntimeDraft()

    init() {}

    init(issue: DaemonIssue) {
        self.title = issue.title
        self.description = issue.description ?? ""
        self.status = issue.status
        self.projectId = issue.projectId ?? ""
        self.parentId = issue.parentId ?? ""
        self.runtime = IssueRuntimeDraft(issue: issue)
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

    let onQueueMessage: (DaemonIssue) -> Void

    var body: some View {
        Group {
            switch appState.issuesRouteDestination {
            case .list:
                IssuesListPage()
            case .detail(let issueId):
                IssueDetailPage(issueId: issueId, onQueueMessage: onQueueMessage)
            }
        }
        .task(id: appState.issuesRouteDestination.issueId ?? "list") {
            appState.reconcileIssuesRouteState()
        }
    }
}

private struct IssuesListPage: View {
    @Environment(AppState.self) private var appState

    private let horizontalInset: CGFloat = 20

    private var visibleIssues: [DaemonIssue] {
        issuesVisible(in: appState.issues, tab: appState.selectedIssuesListTab)
    }

    private var summaryText: String {
        let issueCount = visibleIssues.count
        let suffix = issueCount == 1 ? "conversation" : "conversations"
        return "\(appState.selectedIssuesListTab.title) · \(issueCount) \(suffix)"
    }

    var body: some View {
        VStack(spacing: 0) {
            issuesHeader
            tabBar
            ScrollView {
                VStack(spacing: 0) {
                    summaryBar

                    if visibleIssues.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleIssues) { issue in
                                IssuesListRow(
                                    issue: issue,
                                    isSelected: appState.selectedIssueId == issue.id,
                                    action: { appState.showIssueDetail(issueId: issue.id) }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "0A0A0A"))
    }

    private var issuesHeader: some View {
        HStack {
            Text("CONVERSATIONS")
                .font(GeistFont.sans(size: FontSize.sm, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(Color(hex: "E5E5E5"))
            Spacer()
        }
        .padding(.horizontal, horizontalInset)
        .frame(height: 58)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "1F1F1F"))
                .frame(height: BorderWidth.default)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 18) {
            ForEach(IssuesListTab.allCases, id: \.self) { tab in
                Button {
                    appState.selectedIssuesListTab = tab
                } label: {
                    Text(tab.title)
                        .font(GeistFont.sans(size: FontSize.base, weight: .semibold))
                        .foregroundStyle(appState.selectedIssuesListTab == tab ? Color(hex: "F1F1F1") : Color(hex: "A3A3A3"))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalInset)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "1F1F1F"))
                .frame(height: BorderWidth.default)
        }
    }

    private var summaryBar: some View {
        HStack {
            Text(summaryText)
                .font(GeistFont.sans(size: FontSize.xs, weight: .medium))
                .foregroundStyle(Color(hex: "8E8E8E"))
            Spacer()
        }
        .padding(.horizontal, horizontalInset)
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "151515"))
                .frame(height: BorderWidth.default)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("No conversations in \(appState.selectedIssuesListTab.title.lowercased())")
                .font(Typography.h4)
                .foregroundStyle(Color(hex: "F5F5F5"))
            Text("Conversations own workspaces. Create one from the sidebar to start model work.")
                .font(Typography.body)
                .foregroundStyle(Color(hex: "7A7A7A"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, Spacing.xxl)
    }
}

private struct IssuesListRow: View {
    let issue: DaemonIssue
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Text(issuesListRowTitle(for: issue))
                    .font(GeistFont.sans(size: FontSize.sm, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color(hex: "FFFFFF") : Color(hex: "CDCDCD"))
                    .lineLimit(1)
                    .padding(.leading, CGFloat(issue.requestDepth) * 12)

                Spacer(minLength: Spacing.md)

                Text(formatCompactIssueTimestamp(issue.updatedAt))
                    .font(GeistFont.sans(size: FontSize.xs, weight: .medium))
                    .foregroundStyle(isSelected ? Color(hex: "8E8E8E") : Color(hex: "6F6F6F"))
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? Color(hex: "131313") : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "191919"))
                .frame(height: BorderWidth.default)
        }
    }
}

private struct IssueDetailPage: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let issueId: String
    let onQueueMessage: (DaemonIssue) -> Void

    @State private var newCommentBody = ""
    @State private var isEditingIssue = false
    @State private var issueDraft = IssueEditDraft()
    @State private var isSavingIssue = false
    @State private var issueEditorError: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var selectedIssue: DaemonIssue? {
        appState.issues.first(where: { $0.id == issueId })
    }

    private var queuedMessages: [DaemonIssue] {
        appState.issues.filter { $0.parentId == issueId && $0.hiddenAt == nil }
    }

    private var availableStatusOptions: [String] {
        mergedIssueOptions(defaults: ["backlog", "in_progress", "blocked", "done", "cancelled"], selected: issueDraft.status)
    }

    private var selectableParentIssues: [DaemonIssue] {
        appState.issues.filter { $0.id != issueId }
    }

    private var defaultExecutorId: String? {
        appState.selectedCompany?.ceoAgentId ?? appState.agents.first?.id
    }

    private var runtimeModelOptions: [String] {
        mergedIssueOptions(
            defaults: issueDraft.runtime.provider.defaultModelOptions,
            selected: issueDraft.runtime.model
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Button {
                        appState.showIssuesList()
                    } label: {
                        Label("Back to Conversations", systemImage: "chevron.left")
                            .font(Typography.label)
                            .foregroundStyle(Color(hex: "A3A3A3"))
                    }
                    .buttonStyle(.plain)

                    Text("Conversations")
                        .font(Typography.caption)
                        .foregroundStyle(colors.primary)
                    Text("Conversation Details")
                        .font(Typography.pageTitle)
                }

                if let issue = selectedIssue {
                    DashboardSurfaceCard(title: "Conversation Details") {
                        VStack(alignment: .leading, spacing: Spacing.xl) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(issue.identifier ?? issue.title)
                                        .font(Typography.caption)
                                        .foregroundStyle(colors.primary)
                                    if isEditingIssue {
                                        ShadcnTextField("Conversation title", text: $issueDraft.title, variant: .filled)
                                            .frame(maxWidth: 420)
                                    } else {
                                        Text(issue.title)
                                            .font(Typography.h3)
                                            .foregroundStyle(Color(hex: "F5F5F5"))
                                    }
                                }
                                Spacer()
                                HStack(spacing: Spacing.sm) {
                                    if isEditingIssue {
                                        Button("Cancel") {
                                            discardIssueEdits(for: issue)
                                        }
                                        .buttonSecondary(size: .md)
                                        .disabled(isSavingIssue)

                                        Button {
                                            Task { await saveIssueEdits(for: issue) }
                                        } label: {
                                            HStack(spacing: Spacing.sm) {
                                                if isSavingIssue {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                }
                                                Text("Save Changes")
                                                    .fontWeight(.medium)
                                            }
                                        }
                                        .buttonPrimary(size: .md)
                                        .disabled(!canSaveIssueEdits)
                                    } else {
                                        Button("Edit Conversation") {
                                            beginEditing(issue: issue)
                                        }
                                        .buttonSecondary(size: .md)
                                    }
                                }
                            }

                            if isEditingIssue {
                                BoardFormFieldGroup(
                                    label: "Description",
                                    hint: "Context, decisions, and the next thing a model should pick up all live here."
                                ) {
                                    BoardMultilineInput(
                                        placeholder: "What needs to happen next, what context matters, and what should the next model run understand?",
                                        text: $issueDraft.description,
                                        minHeight: 140
                                    )
                                }
                            } else if let description = issue.description, !description.isEmpty {
                                DetailSection(title: "Description", text: description)
                            }

                            if isEditingIssue {
                                issueEditorFields
                            } else {
                                DetailGrid(items: [
                                    ("Status", humanizedIssueValue(issue.status)),
                                    ("Model", issueModelLabel(issue, agents: appState.agents)),
                                    ("Project", projectLabel(for: issue.projectId)),
                                    ("Parent Conversation", parentIssueLabel(for: issue.parentId)),
                                    ("Depth", "\(issue.requestDepth)")
                                ])
                            }

                            if let issueEditorError {
                                BoardInlineMessage(text: issueEditorError, tone: .error)
                            }

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                HStack {
                                    Text("Queued Messages")
                                        .font(Typography.h4)
                                        .foregroundStyle(Color(hex: "F5F5F5"))
                                    Spacer()
                                    Button("Queue Message") {
                                        onQueueMessage(issue)
                                    }
                                    .buttonSecondary(size: .md)
                                }

                                if queuedMessages.isEmpty {
                                    Text("No queued messages yet.")
                                        .font(Typography.body)
                                        .foregroundStyle(colors.mutedForeground)
                                } else {
                                    ForEach(queuedMessages) { child in
                                        Button {
                                            appState.showIssueDetail(issueId: child.id)
                                        } label: {
                                            HStack {
                                                Text(child.identifier ?? child.title)
                                                Spacer()
                                                StatusPill(text: child.status)
                                            }
                                            .padding(.vertical, Spacing.xxs)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Messages")
                                    .font(Typography.h4)
                                    .foregroundStyle(Color(hex: "F5F5F5"))

                                let comments = appState.issueComments[issue.id] ?? []
                                if comments.isEmpty {
                                    Text("No messages yet.")
                                        .font(Typography.body)
                                        .foregroundStyle(colors.mutedForeground)
                                } else {
                                    ForEach(comments) { comment in
                                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                                            Text(issueCommentAuthorLabel(appState.agents, comment: comment))
                                                .font(Typography.captionMedium)
                                                .foregroundStyle(colors.primary)
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

                                    Button("Send Message") {
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
                                                boardLogger.error("Failed to add conversation message: \(error)")
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
                        title: "Conversation unavailable",
                        message: "This conversation no longer exists. Return to the list to choose another conversation."
                    )
                }
            }
            .padding(Spacing.xl)
        }
        .background(colors.background)
        .task(id: selectedIssue?.id) {
            if let issue = selectedIssue {
                await appState.refreshIssueComments(issueId: issue.id)
                isEditingIssue = false
                syncIssueDraft(from: issue)
            } else {
                appState.reconcileIssuesRouteState()
                isEditingIssue = false
                issueEditorError = nil
            }
        }
    }

    @ViewBuilder
    private var issueEditorFields: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            BoardFormFieldGroup(
                label: "Status",
                hint: "Moves the conversation through the board lifecycle and can trigger follow-up automation."
            ) {
                BoardMenuField(valueText: humanizedIssueValue(issueDraft.status)) {
                    ForEach(availableStatusOptions, id: \.self) { status in
                        Button(humanizedIssueValue(status)) {
                            issueDraft.status = status
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Project",
                hint: "Optional project anchor for repo context and workspace routing."
            ) {
                BoardMenuField(
                    valueText: projectLabel(for: issueDraft.projectId),
                    isPlaceholder: issueDraft.projectId.isEmpty
                ) {
                    Button("No project") {
                        issueDraft.projectId = ""
                    }
                    ForEach(appState.projects) { project in
                        Button(project.name) {
                            issueDraft.projectId = project.id
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Parent Conversation",
                hint: "Nest this under another conversation, or clear the parent to move it back to the root."
            ) {
                BoardMenuField(
                    valueText: parentIssueLabel(for: issueDraft.parentId.nonEmpty),
                    isPlaceholder: issueDraft.parentId.isEmpty
                ) {
                    Button("No parent conversation") {
                        issueDraft.parentId = ""
                    }
                    ForEach(selectableParentIssues) { parentIssue in
                        Button(parentIssue.identifier ?? parentIssue.title) {
                            issueDraft.parentId = parentIssue.id
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Provider",
                hint: "Choose which local runtime handles this conversation."
            ) {
                BoardMenuField(valueText: issueDraft.runtime.provider.title) {
                    ForEach(ConversationRuntimeProvider.allCases) { provider in
                        Button(provider.title) {
                            issueDraft.runtime.provider = provider
                            if provider != .claude {
                                issueDraft.runtime.planMode = false
                            }
                            if !provider.defaultModelOptions.contains(issueDraft.runtime.model) {
                                issueDraft.runtime.model = "default"
                            }
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Model",
                hint: "Pick the model identifier the local runtime should use."
            ) {
                BoardMenuField(valueText: runtimeModelDisplayName(issueDraft.runtime.model)) {
                    ForEach(runtimeModelOptions, id: \.self) { option in
                        Button(runtimeModelDisplayName(option)) {
                            issueDraft.runtime.model = option
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Thinking effort",
                hint: "Controls how much reasoning time the model can spend before acting."
            ) {
                BoardMenuField(valueText: humanizedIssueValue(issueDraft.runtime.thinkingEffort)) {
                    ForEach(
                        mergedIssueOptions(
                            defaults: IssueRuntimeDraft.thinkingEffortOptions,
                            selected: issueDraft.runtime.thinkingEffort
                        ),
                        id: \.self
                    ) { option in
                        Button(humanizedIssueValue(option)) {
                            issueDraft.runtime.thinkingEffort = option
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Plan mode",
                hint: "Claude can stay in planning mode until you explicitly move the conversation forward."
            ) {
                BoardMenuField(
                    valueText: issueDraft.runtime.provider == .claude && issueDraft.runtime.planMode
                        ? "Claude plan mode"
                        : "Off"
                ) {
                    Button("Off") {
                        issueDraft.runtime.planMode = false
                    }
                    Button("Claude plan mode") {
                        issueDraft.runtime.provider = .claude
                        issueDraft.runtime.planMode = true
                    }
                }
            }

            BoardCheckboxRow(
                title: issueDraft.runtime.provider.browserLabel,
                subtitle: issueDraft.runtime.provider.browserHint,
                isOn: $issueDraft.runtime.enableChrome
            )

            BoardCheckboxRow(
                title: "Skip permissions",
                subtitle: "Let the model run without daemon approval prompts.",
                isOn: $issueDraft.runtime.skipPermissions
            )
        }
    }

    private var canSaveIssueEdits: Bool {
        !isSavingIssue
            && !issueDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func mergedIssueOptions(defaults: [String], selected: String) -> [String] {
        let trimmedSelected = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        var options: [String] = []
        if !trimmedSelected.isEmpty {
            options.append(trimmedSelected)
        }
        for value in defaults where !options.contains(value) {
            options.append(value)
        }
        return options
    }

    private func projectLabel(for projectId: String?) -> String {
        guard let projectId, !projectId.isEmpty else { return "No project" }
        return appState.projects.first(where: { $0.id == projectId })?.name ?? projectId
    }

    private func parentIssueLabel(for parentIssueId: String?) -> String {
        guard let parentIssueId, !parentIssueId.isEmpty else { return "No parent conversation" }
        let parentIssue = appState.issues.first(where: { $0.id == parentIssueId })
        return parentIssue?.identifier ?? parentIssue?.title ?? parentIssueId
    }

    private func humanizedIssueValue(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func beginEditing(issue: DaemonIssue) {
        syncIssueDraft(from: issue)
        issueEditorError = nil
        isEditingIssue = true
    }

    private func discardIssueEdits(for issue: DaemonIssue) {
        syncIssueDraft(from: issue)
        issueEditorError = nil
        isEditingIssue = false
    }

    private func syncIssueDraft(from issue: DaemonIssue) {
        issueDraft = IssueEditDraft(issue: issue)
    }

    private func saveIssueEdits(for issue: DaemonIssue) async {
        isSavingIssue = true
        issueEditorError = nil
        defer { isSavingIssue = false }

        let trimmedTitle = issueDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = issueDraft.description.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            issueEditorError = "Conversation title is required."
            return
        }

        var params: [String: Any] = [
            "issue_id": issue.id,
            "title": trimmedTitle,
            "status": issueDraft.status,
        ]
        params["description"] = trimmedDescription.isEmpty ? NSNull() : trimmedDescription
        params["project_id"] = issueDraft.projectId.isEmpty ? NSNull() : issueDraft.projectId
        params["parent_id"] = issueDraft.parentId.isEmpty ? NSNull() : issueDraft.parentId
        params["assignee_adapter_overrides"] = issueDraft.runtime.asAdapterOverrides()
        if let defaultExecutorId, issue.assigneeAgentId?.isEmpty != false {
            params["assignee_agent_id"] = defaultExecutorId
        }

        do {
            let updatedIssue = try await appState.updateIssue(params: params)
            issueDraft = IssueEditDraft(issue: updatedIssue)
            isEditingIssue = false
        } catch {
            issueEditorError = error.localizedDescription
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

    let onCreate: (String, String?, Int?, String?) async throws -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var budget = ""
    @State private var brandColor = "#0F766E"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !isSaving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        BoardDialogScaffold(
            title: "Create Space",
            subtitle: "Add a new space shell. Unbound will prepare its default local executor automatically."
        ) {
            BoardFormFieldGroup(
                label: "Space Name",
                hint: "Used in the spaces rail, sidebar, and dashboard."
            ) {
                ShadcnTextField("Acme Systems", text: $name, variant: .filled)
            }

            BoardFormFieldGroup(
                label: "Description",
                hint: "Optional context for how this space should operate inside Unbound."
            ) {
                BoardMultilineInput(
                    placeholder: "Internal platform team, design systems, launch operations, or another working context...",
                    text: $description,
                    minHeight: 88
                )
            }

            BoardFormFieldGroup(
                label: "Monthly Budget (cents)",
                hint: "Stored as cents so the board can track spend precisely."
            ) {
                ShadcnTextField("500000", text: $budget, variant: .filled)
            }

            BoardFormFieldGroup(
                label: "Brand Color",
                hint: "Optional hex color for the space badge and related accents."
            ) {
                ShadcnTextField("#0F766E", text: $brandColor, variant: .filled)
            }

            if let errorMessage {
                BoardInlineMessage(text: errorMessage, tone: .error)
            }
        } footer: {
            HStack(spacing: Spacing.sm) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonSecondary(size: .md)
                .disabled(isSaving)

                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Create Space")
                            .fontWeight(.medium)
                    }
                }
                .buttonPrimary(size: .md)
                .disabled(!canCreate)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await onCreate(
                name.trimmingCharacters(in: .whitespacesAndNewlines),
                description.nonEmpty,
                Int(budget),
                brandColor.nonEmpty
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
    let requiresBoardApproval: Bool
    let onCreate: ([String: Any]) async throws -> Void

    @State private var name = ""
    @State private var role = "general"
    @State private var title = ""
    @State private var icon = "person.crop.circle"
    @State private var adapterType = "process"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !isSaving
            && companyId != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        BoardDialogScaffold(
            title: requiresBoardApproval ? "Hire Agent" : "Create Agent",
            subtitle: requiresBoardApproval
                ? "Submit a governed hire request. The agent record appears immediately, and the board creates a linked hire approval before the agent can start working."
                : "Create a new space agent through the same governed hire flow the CEO uses during runs."
        ) {
            BoardFormFieldGroup(
                label: "Name",
                hint: "The human-readable name shown in the sidebar, approvals, and issue flows."
            ) {
                ShadcnTextField("Customer Ops", text: $name, variant: .filled)
            }

            BoardFormFieldGroup(
                label: "Role",
                hint: "Used for agent defaults and lightweight routing inside the board and approval payload."
            ) {
                ShadcnTextField("general", text: $role, variant: .filled)
            }

            BoardFormFieldGroup(
                label: "Title",
                hint: "Optional display title shown in dashboards and issue details."
            ) {
                ShadcnTextField("Head of Support", text: $title, variant: .filled)
            }

            BoardFormFieldGroup(
                label: "Icon",
                hint: "Optional SF Symbol or icon key used by the board UI."
            ) {
                ShadcnTextField("person.crop.circle", text: $icon, variant: .filled)
            }

            BoardInlineMessage(
                text: requiresBoardApproval
                    ? "This space requires approval for new agents. Saving here creates the pending agent and a hire approval together."
                    : "This space does not require board approval, but hires still go through the board-native path so the request stays visible in the UI and activity log.",
                tone: .info
            )

            BoardFormFieldGroup(
                label: "Adapter Type",
                hint: "Defaults to `process` for local process-backed execution."
            ) {
                ShadcnTextField("process", text: $adapterType, variant: .filled)
            }

            if let errorMessage {
                BoardInlineMessage(text: errorMessage, tone: .error)
            }
        } footer: {
            HStack(spacing: Spacing.sm) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonSecondary(size: .md)
                .disabled(isSaving)

                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(requiresBoardApproval ? "Submit Hire Request" : "Create Agent")
                            .fontWeight(.medium)
                    }
                }
                .buttonPrimary(size: .md)
                .disabled(!canCreate)
            }
        }
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
    let defaultExecutorId: String?
    let projects: [DaemonProject]
    let issues: [DaemonIssue]
    let mode: ConversationComposerMode
    let onCreate: ([String: Any]) async throws -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var selectedProjectId: String
    @State private var selectedParentIssueId: String
    @State private var runtimeDraft: IssueRuntimeDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        companyId: String?,
        defaultExecutorId: String?,
        projects: [DaemonProject],
        issues: [DaemonIssue],
        mode: ConversationComposerMode = .conversation,
        defaultProjectId: String? = nil,
        defaultParentIssueId: String? = nil,
        onCreate: @escaping ([String: Any]) async throws -> Void
    ) {
        self.companyId = companyId
        self.defaultExecutorId = defaultExecutorId
        self.projects = projects
        self.issues = issues
        self.mode = mode
        self.onCreate = onCreate
        _selectedProjectId = State(initialValue: defaultProjectId ?? "")
        _selectedParentIssueId = State(initialValue: defaultParentIssueId ?? "")
        _runtimeDraft = State(initialValue: IssueRuntimeDraft())
    }

    private var canCreate: Bool {
        !isSaving
            && companyId != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (mode == .conversation || !selectedParentIssueId.isEmpty)
    }

    private var selectedProjectLabel: String {
        projects.first(where: { $0.id == selectedProjectId })?.name ?? "No project"
    }

    private var selectedParentIssueLabel: String {
        issues.first(where: { $0.id == selectedParentIssueId })?.identifier
            ?? issues.first(where: { $0.id == selectedParentIssueId })?.title
            ?? "No parent conversation"
    }

    private var sheetTitle: String {
        mode.title
    }

    private var runtimeModelOptions: [String] {
        mergedConversationOptions(
            defaults: runtimeDraft.provider.defaultModelOptions,
            selected: runtimeDraft.model
        )
    }

    private var runtimeThinkingEffortOptions: [String] {
        mergedConversationOptions(
            defaults: IssueRuntimeDraft.thinkingEffortOptions,
            selected: runtimeDraft.thinkingEffort
        )
    }

    private var sheetSubtitle: String {
        switch mode {
        case .conversation:
            return "Create a new conversation, choose its local model, and optionally route it to a project or parent conversation."
        case .queuedMessage:
            return "Queue a follow-up message under this conversation so it stays ready for the next model pass."
        }
    }

    var body: some View {
        BoardDialogScaffold(
            title: sheetTitle,
            subtitle: sheetSubtitle
        ) {
            BoardFormFieldGroup(
                label: mode == .queuedMessage ? "Message" : "Title",
                hint: mode == .queuedMessage
                    ? "This becomes the queued follow-up that stays attached to the parent conversation."
                    : "This becomes the main conversation title and the default workspace label."
            ) {
                ShadcnTextField(
                    mode == .queuedMessage ? "Follow up on the failing deploy logs" : "Investigate CI flake",
                    text: $title,
                    variant: .filled
                )
            }

            BoardFormFieldGroup(
                label: "Description",
                hint: mode == .queuedMessage
                    ? "Optional extra context for the queued follow-up."
                    : "Optional background, acceptance criteria, or context for the conversation."
            ) {
                BoardMultilineInput(
                    placeholder: mode == .queuedMessage
                        ? "What should the next model run keep in mind when it picks this up?"
                        : "What needs to happen, how should success be measured, and what context should the next model run keep in mind?",
                    text: $description,
                    minHeight: 96
                )
            }

            BoardFormFieldGroup(
                label: "Project",
                hint: "Optional project anchor for workspace routing and repo context."
            ) {
                BoardMenuField(
                    valueText: selectedProjectLabel,
                    isPlaceholder: selectedProjectId.isEmpty
                ) {
                    Button("No project") {
                        selectedProjectId = ""
                    }
                    ForEach(projects) { project in
                        Button(project.name) {
                            selectedProjectId = project.id
                        }
                    }
                }
            }

            if mode == .conversation {
                BoardFormFieldGroup(
                    label: "Parent Conversation",
                    hint: "Use this to nest follow-up work under an existing conversation."
                ) {
                    BoardMenuField(
                        valueText: selectedParentIssueLabel,
                        isPlaceholder: selectedParentIssueId.isEmpty
                    ) {
                        Button("No parent conversation") {
                            selectedParentIssueId = ""
                        }
                        ForEach(issues) { issue in
                            Button(issue.identifier ?? issue.title) {
                                selectedParentIssueId = issue.id
                            }
                        }
                    }
                }
            } else {
                BoardFormFieldGroup(
                    label: "Parent Conversation",
                    hint: "Queued messages stay attached to this conversation."
                ) {
                    Text(selectedParentIssueLabel)
                        .font(Typography.body)
                        .foregroundStyle(Color(hex: "F5F5F5"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.md)
                        .background(Color(hex: "111111"))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
            }

            BoardFormFieldGroup(
                label: "Provider",
                hint: "Choose which local runtime handles this conversation."
            ) {
                BoardMenuField(valueText: runtimeDraft.provider.title) {
                    ForEach(ConversationRuntimeProvider.allCases) { provider in
                        Button(provider.title) {
                            runtimeDraft.provider = provider
                            if provider != .claude {
                                runtimeDraft.planMode = false
                            }
                            if !provider.defaultModelOptions.contains(runtimeDraft.model) {
                                runtimeDraft.model = "default"
                            }
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Model",
                hint: "Pick the model identifier the local runtime should use."
            ) {
                BoardMenuField(valueText: runtimeModelDisplayName(runtimeDraft.model)) {
                    ForEach(runtimeModelOptions, id: \.self) { option in
                        Button(runtimeModelDisplayName(option)) {
                            runtimeDraft.model = option
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Thinking effort",
                hint: "Controls how much reasoning time the model can spend before acting."
            ) {
                BoardMenuField(valueText: humanizedConversationValue(runtimeDraft.thinkingEffort)) {
                    ForEach(runtimeThinkingEffortOptions, id: \.self) { option in
                        Button(humanizedConversationValue(option)) {
                            runtimeDraft.thinkingEffort = option
                        }
                    }
                }
            }

            BoardFormFieldGroup(
                label: "Plan mode",
                hint: "Claude can stay in planning mode until you explicitly move the conversation forward."
            ) {
                BoardMenuField(
                    valueText: runtimeDraft.provider == .claude && runtimeDraft.planMode
                        ? "Claude plan mode"
                        : "Off"
                ) {
                    Button("Off") {
                        runtimeDraft.planMode = false
                    }
                    Button("Claude plan mode") {
                        runtimeDraft.provider = .claude
                        runtimeDraft.planMode = true
                    }
                }
            }

            BoardCheckboxRow(
                title: runtimeDraft.provider.browserLabel,
                subtitle: runtimeDraft.provider.browserHint,
                isOn: $runtimeDraft.enableChrome
            )

            BoardCheckboxRow(
                title: "Skip permissions",
                subtitle: "Let the model run without daemon approval prompts.",
                isOn: $runtimeDraft.skipPermissions
            )

            if let errorMessage {
                BoardInlineMessage(text: errorMessage, tone: .error)
            }
        } footer: {
            HStack(spacing: Spacing.sm) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonSecondary(size: .md)
                .disabled(isSaving)

                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(mode == .queuedMessage ? "Queue Message" : "Create Conversation")
                            .fontWeight(.medium)
                    }
                }
                .buttonPrimary(size: .md)
                .disabled(!canCreate)
            }
        }
    }

    private func save() async {
        guard let companyId else { return }

        isSaving = true
        defer { isSaving = false }

        var params: [String: Any] = [
            "company_id": companyId,
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "status": "backlog",
        ]
        if let description = description.nonEmpty { params["description"] = description }
        if !selectedProjectId.isEmpty { params["project_id"] = selectedProjectId }
        if !selectedParentIssueId.isEmpty { params["parent_id"] = selectedParentIssueId }
        params["assignee_adapter_overrides"] = runtimeDraft.asAdapterOverrides()
        if let defaultExecutorId, !defaultExecutorId.isEmpty {
            params["assignee_agent_id"] = defaultExecutorId
        }

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

#if DEBUG

#Preview("First Space Setup") {
    CreateFirstCompanyView()
        .environment(AppState())
        .frame(width: 1180, height: 780)
}

#Preview("CEO Setup Required") {
    CreateCEOAgentView()
        .environment(makeCEOOnboardingPreviewState(step: .createCEO))
        .frame(width: 1180, height: 780)
}

#Preview("CEO Bootstrap Conversation Step") {
    CreateCEOAgentView()
        .environment(makeCEOOnboardingPreviewState(step: .bootstrapIssue))
        .frame(width: 1180, height: 780)
}

#Preview("Board Settings") {
    BoardRootView()
        .environment(makeBoardRootPreviewState(selectedScreen: .settings))
        .frame(width: 1180, height: 780)
}

#Preview("Initial Space Load Error") {
    InitialCompanyLoadErrorView(
        message: "The board schema could not be read from the local daemon. Check the daemon logs and try again.",
        onRetry: {}
    )
    .frame(width: 1180, height: 780)
}

#Preview("Create Space Sheet") {
    CreateCompanySheet { _, _, _, _ in }
        .frame(width: 520, height: 420)
}

#Preview("Create Agent Sheet") {
    CreateAgentSheet(
        companyId: "company-1",
        defaultReportsTo: nil,
        requiresBoardApproval: true,
        onCreate: { _ in }
    )
    .frame(width: 520, height: 440)
}

#Preview("Create Conversation Sheet") {
    CreateIssueSheet(
        companyId: "company-1",
        defaultExecutorId: "agent-1",
        projects: [],
        issues: [],
        onCreate: { _ in }
    )
    .frame(width: 620, height: 700)
}

#endif

#if DEBUG
@MainActor
private func makeBoardRootPreviewState(selectedScreen: AppScreen) -> AppState {
    let appState = AppState()
    let company = DaemonCompany(
        id: "company-1",
        name: "Acme",
        description: "Board shell preview space",
        status: "active",
        issuePrefix: "ACM",
        issueCounter: 1,
        budgetMonthlyCents: 0,
        spentMonthlyCents: 0,
        requireBoardApprovalForNewAgents: true,
        brandColor: "F59E0B",
        ceoAgentId: "agent-1",
        createdAt: "2026-03-14T00:00:00Z",
        updatedAt: "2026-03-14T00:00:00Z"
    )
    let agent = DaemonAgent(
        id: "agent-1",
        companyId: company.id,
        name: "CEO",
        slug: "ceo",
        role: "ceo",
        title: "Chief Executive Officer",
        icon: "crown",
        status: "idle",
        reportsTo: nil,
        capabilities: nil,
        adapterType: "process",
        adapterConfig: nil,
        runtimeConfig: nil,
        budgetMonthlyCents: 0,
        spentMonthlyCents: 0,
        permissions: nil,
        lastHeartbeatAt: nil,
        metadata: nil,
        homePath: "/tmp/acme/agents/ceo",
        instructionsPath: "/tmp/acme/agents/ceo/AGENTS.md",
        createdAt: "2026-03-14T00:00:00Z",
        updatedAt: "2026-03-14T00:00:00Z"
    )

    appState.configureForPreview(
        companies: [company],
        agents: [agent],
        selectedCompanyId: company.id,
        hasCompletedInitialCompanyLoad: true,
        selectedScreen: selectedScreen
    )
    return appState
}

@MainActor
private func makeCEOOnboardingPreviewState(step: BoardOnboardingStep) -> AppState {
    let appState = AppState()
    let company = DaemonCompany(
        id: "company-1",
        name: "Acme",
        description: nil,
        status: "active",
        issuePrefix: "ACM",
        issueCounter: 1,
        budgetMonthlyCents: 0,
        spentMonthlyCents: 0,
        requireBoardApprovalForNewAgents: true,
        brandColor: nil,
        ceoAgentId: step == .bootstrapIssue ? "agent-1" : nil,
        createdAt: "2026-03-14T00:00:00Z",
        updatedAt: "2026-03-14T00:00:00Z"
    )
    let agent = DaemonAgent(
        id: "agent-1",
        companyId: company.id,
        name: "CEO",
        slug: "ceo",
        role: "ceo",
        title: "Chief Executive Officer",
        icon: "crown",
        status: "idle",
        reportsTo: nil,
        capabilities: nil,
        adapterType: "process",
        adapterConfig: nil,
        runtimeConfig: nil,
        budgetMonthlyCents: 0,
        spentMonthlyCents: 0,
        permissions: nil,
        lastHeartbeatAt: nil,
        metadata: nil,
        homePath: "/tmp/acme/agents/ceo",
        instructionsPath: "/tmp/acme/agents/ceo/AGENTS.md",
        createdAt: "2026-03-14T00:00:00Z",
        updatedAt: "2026-03-14T00:00:00Z"
    )
    var onboardingState = BoardOnboardingState.initial(companyId: company.id, companyName: company.name)
    onboardingState.step = step
    onboardingState.ceoAgentId = step == .bootstrapIssue ? agent.id : nil

    appState.configureForPreview(
        companies: [company],
        agents: step == .bootstrapIssue ? [agent] : [],
        selectedCompanyId: company.id,
        hasCompletedInitialCompanyLoad: true,
        boardOnboardingState: onboardingState
    )
    return appState
}
#endif

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

private func shortRunTitle(_ runId: String) -> String {
    "Run \(runId.prefix(8))"
}

private func agentRunSummary(_ run: DaemonAgentRun) -> String {
    if let error = run.error, !error.isEmpty {
        return error
    }
    if let stdoutExcerpt = run.stdoutExcerpt, !stdoutExcerpt.isEmpty {
        return stdoutExcerpt
    }
    if let stderrExcerpt = run.stderrExcerpt, !stderrExcerpt.isEmpty {
        return stderrExcerpt
    }
    if let wakeReason = run.wakeReason {
        return agentRunWakeReasonLabel(Optional(wakeReason))
    }
    if let triggerDetail = run.triggerDetail {
        return agentRunTriggerDetailLabel(Optional(triggerDetail))
    }
    return "Waiting for run output."
}

private func agentRunStatusLabel(_ status: String) -> String {
    switch status {
    case "queued":
        return "Queued"
    case "running":
        return "Running"
    case "succeeded":
        return "Succeeded"
    case "failed":
        return "Failed"
    case "cancelled":
        return "Cancelled"
    case "timed_out":
        return "Timed Out"
    default:
        return status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func agentRunInvocationSourceLabel(_ source: String) -> String {
    switch source {
    case "timer":
        return "Timer"
    case "assignment":
        return "Assignment"
    case "on_demand":
        return "On Demand"
    case "automation":
        return "Automation"
    default:
        return source.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func agentRunTriggerDetailLabel(_ triggerDetail: String?) -> String {
    guard let triggerDetail, !triggerDetail.isEmpty else { return "None" }
    switch triggerDetail {
    case "manual":
        return "Manual"
    case "system":
        return "System"
    case "ping":
        return "Ping"
    case "callback":
        return "Callback"
    default:
        return triggerDetail.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func agentRunWakeReasonLabel(_ wakeReason: String?) -> String {
    guard let wakeReason, !wakeReason.isEmpty else { return "None" }
    switch wakeReason {
    case "heartbeat_timer":
        return "Heartbeat Timer"
    case "issue_assigned":
        return "Conversation Routed"
    case "issue_status_changed":
        return "Conversation Status Changed"
    case "issue_checked_out":
        return "Conversation Checked Out"
    case "issue_commented":
        return "Conversation Messaged"
    case "issue_comment_mentioned":
        return "Message Mentioned"
    case "issue_reopened_via_comment":
        return "Conversation Reopened"
    case "approval_approved":
        return "Approval Approved"
    case "issue_execution_promoted":
        return "Execution Promoted"
    case "stale_checkout_run":
        return "Stale Checkout Run"
    default:
        return wakeReason.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func agentRunEventLabel(_ eventType: String) -> String {
    eventType.replacingOccurrences(of: "_", with: " ").capitalized
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

private func conversationActivitySummary(_ issue: DaemonIssue) -> String {
    if issue.completedAt != nil {
        return "Conversation completed"
    }
    if issue.cancelledAt != nil {
        return "Conversation cancelled"
    }
    if issue.startedAt != nil {
        return "Work started"
    }
    if issue.workspaceSessionId != nil {
        return "Workspace attached"
    }
    return "Conversation updated"
}

private func anyCodableString(_ dictionary: [String: AnyCodableValue]?, key: String) -> String? {
    guard let value = dictionary?[key]?.value as? String else { return nil }
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
}

private func anyCodableBool(_ dictionary: [String: AnyCodableValue]?, key: String) -> Bool {
    guard let value = dictionary?[key]?.value else { return false }
    if let boolValue = value as? Bool {
        return boolValue
    }
    if let stringValue = value as? String {
        return ["1", "true", "yes", "on"].contains(stringValue.lowercased())
    }
    if let numberValue = value as? NSNumber {
        return numberValue.boolValue
    }
    return false
}

private func mergedConversationOptions(defaults: [String], selected: String) -> [String] {
    let trimmedSelected = selected.trimmingCharacters(in: .whitespacesAndNewlines)
    var options: [String] = []
    if !trimmedSelected.isEmpty {
        options.append(trimmedSelected)
    }
    for value in defaults where !options.contains(value) {
        options.append(value)
    }
    return options
}

private func humanizedConversationValue(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}

private func runtimeModelDisplayName(_ value: String) -> String {
    value.caseInsensitiveCompare("default") == .orderedSame ? "Default" : value
}

private func providerLabel(command: String?, model: String?, extraValues: [String] = []) -> String? {
    let combinedValues = ([command, model] + extraValues.map(Optional.some))
        .compactMap { $0?.lowercased() }

    if combinedValues.contains(where: { $0.contains("codex") }) {
        return "Codex"
    }
    if combinedValues.contains(where: { $0.contains("claude") }) {
        return "Claude"
    }
    if combinedValues.contains(where: { $0.contains("openai") }) {
        return "OpenAI"
    }
    if combinedValues.contains(where: { $0.contains("gemini") }) {
        return "Gemini"
    }
    return nil
}

private func runtimeProvider(command: String?, model: String?) -> ConversationRuntimeProvider {
    providerLabel(command: command, model: model) == "Codex" ? .codex : .claude
}

private func providerLabel(for agent: DaemonAgent) -> String? {
    providerLabel(
        command: anyCodableString(agent.runtimeConfig, key: "command")
            ?? anyCodableString(agent.adapterConfig, key: "command"),
        model: anyCodableString(agent.runtimeConfig, key: "model")
            ?? anyCodableString(agent.adapterConfig, key: "model"),
        extraValues: [
            anyCodableString(agent.runtimeConfig, key: "provider"),
            anyCodableString(agent.adapterConfig, key: "provider"),
            anyCodableString(agent.runtimeConfig, key: "adapter"),
            anyCodableString(agent.adapterConfig, key: "adapter"),
            agent.adapterType,
        ]
        .compactMap { $0 }
    )
}

private func conversationModelLabel(_ agent: DaemonAgent) -> String {
    if let model = anyCodableString(agent.runtimeConfig, key: "model")
        ?? anyCodableString(agent.adapterConfig, key: "model"),
       model.caseInsensitiveCompare("default") != .orderedSame {
        return model
    }

    return providerLabel(for: agent) ?? "Default model"
}

private func conversationModelLabelByAgentId(_ agents: [DaemonAgent], agentId: String?) -> String? {
    guard let agentId, !agentId.isEmpty else { return nil }
    guard let agent = agents.first(where: { $0.id == agentId }) else { return agentId }
    return conversationModelLabel(agent)
}

private func issueModelLabel(_ issue: DaemonIssue, agents: [DaemonAgent]) -> String {
    let command = anyCodableString(issue.assigneeAdapterOverrides, key: "command")
    let model = anyCodableString(issue.assigneeAdapterOverrides, key: "model")
    if let model, model.caseInsensitiveCompare("default") != .orderedSame {
        return model
    }
    if let provider = providerLabel(command: command, model: model) {
        return provider
    }
    return conversationModelLabelByAgentId(agents, agentId: issue.assigneeAgentId) ?? "Claude"
}

private func workspaceModelLabel(
    _ workspace: DaemonWorkspace,
    issues: [DaemonIssue],
    agents: [DaemonAgent]
) -> String? {
    if let issueId = workspace.issueId,
       let issue = issues.first(where: { $0.id == issueId }) {
        return issueModelLabel(issue, agents: agents)
    }
    return conversationModelLabelByAgentId(agents, agentId: workspace.agentId)
}

private func issueCommentAuthorLabel(_ agents: [DaemonAgent], comment: DaemonIssueComment) -> String {
    if let authorAgentId = comment.authorAgentId {
        return conversationModelLabelByAgentId(agents, agentId: authorAgentId) ?? authorAgentId
    }
    if let authorUserId = comment.authorUserId {
        return authorUserId == "local-board" ? "You" : "You"
    }
    return "System"
}

private func isRootConversationIssue(_ issue: DaemonIssue) -> Bool {
    issue.parentId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
}

func issuesVisible(
    in issues: [DaemonIssue],
    tab: IssuesListTab,
    now: Date = Date(),
    calendar: Calendar = .current
) -> [DaemonIssue] {
    let visibleIssues = issues.filter { $0.hiddenAt == nil && isRootConversationIssue($0) }

    switch tab {
    case .all:
        return visibleIssues
    case .new:
        guard let threshold = calendar.date(byAdding: .day, value: -7, to: now) else {
            return visibleIssues
        }
        return visibleIssues.filter { issue in
            guard let createdAt = parsedDate(issue.createdAt) else { return false }
            return createdAt >= threshold
        }
    }
}

private func issuesListRowTitle(for issue: DaemonIssue) -> String {
    guard let identifier = issue.identifier, !identifier.isEmpty else {
        return issue.title
    }
    return "\(identifier)  \(issue.title)"
}

private func formatCompactIssueTimestamp(
    _ value: String?,
    now: Date = Date(),
    calendar: Calendar = .current
) -> String {
    guard let date = parsedDate(value) else { return "Unknown" }

    let seconds = now.timeIntervalSince(date)
    if seconds < 60 {
        return "Just now"
    }
    if seconds < 3600 {
        return "\(max(Int(seconds / 60), 1))m"
    }
    if seconds < 86_400 {
        return "\(max(Int(seconds / 3600), 1))h"
    }
    if calendar.isDateInYesterday(date) {
        return "Yesterday"
    }

    let startOfNow = calendar.startOfDay(for: now)
    let startOfDate = calendar.startOfDay(for: date)
    if let dayDelta = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day,
       dayDelta < 7 {
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    return date.formatted(.dateTime.month(.abbreviated).day())
}

private func formatRelativeDate(_ value: String?) -> String {
    guard let date = parsedDate(value) else { return "Unknown" }
    return date.formatted(.relative(presentation: .named))
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
