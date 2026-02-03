//
//  WorkspaceView.swift
//  mockup-macos
//
//  Shadcn-styled main workspace view.
//

import SwiftUI

struct WorkspaceView: View {
    @Environment(MockAppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    // Chat state
    @State private var chatInput: String = ""
    @State private var selectedModel: AIModel = .opus
    @State private var selectedThinkMode: ThinkMode = .none
    @State private var isPlanMode: Bool = false

    // Version control state
    @State private var selectedSidebarTab: RightSidebarTab = .changes

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    // MARK: - Computed Properties

    /// Active sessions
    private var sessions: [Session] {
        appState.sessions.values.flatMap { $0 }
    }

    /// Selected session
    private var selectedSession: Session? {
        appState.selectedSession
    }

    /// Get the repository for the selected session
    private var selectedRepository: Repository? {
        appState.selectedRepository
    }

    /// Get the working directory path for the selected session
    private var workingDirectoryPath: String? {
        guard let session = selectedSession else { return nil }

        // If session is a worktree, use its worktree path
        if session.isWorktree, let worktreePath = session.worktreePath {
            return worktreePath
        }

        // Otherwise use the repository path
        return selectedRepository?.path
    }

    /// Space needed for traffic lights (close, minimize, zoom)
    private let trafficLightWidth: CGFloat = 78

    /// Titlebar height (standard macOS titlebar)
    private let titlebarHeight: CGFloat = 28

    var body: some View {
        ZStack(alignment: .top) {
            // Main content area with split panels
            HSplitView {
                // Left sidebar - Sessions
                WorkspacesSidebar(
                    onOpenSettings: {
                        appState.showSettings = true
                    },
                    onAddRepository: {
                        // Mock add repository action
                    },
                    onCreateSessionForRepository: { _, _ in
                        // Mock create session action
                    }
                )
                .frame(minWidth: 120, idealWidth: 168, maxWidth: 240)

                // Center - Chat Panel
                if selectedSession != nil {
                    ChatPanel(
                        session: selectedSession,
                        repository: selectedRepository,
                        chatInput: $chatInput,
                        selectedModel: $selectedModel,
                        selectedThinkMode: $selectedThinkMode,
                        isPlanMode: $isPlanMode
                    )
                    .frame(minWidth: 400)
                } else {
                    WorkspaceEmptyState(
                        hasRepositories: !sessions.isEmpty,
                        onAddRepository: {}
                    )
                    .frame(minWidth: 400)
                }

                // Right sidebar - Git Operations
                RightSidebarPanel(
                    selectedTab: $selectedSidebarTab,
                    workingDirectory: workingDirectoryPath
                )
                .frame(minWidth: 250, idealWidth: 450)
            }
            .padding(.top, titlebarHeight)

            // Custom titlebar row (same line as traffic lights)
            WindowToolbar(content: {
                ZStack {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: trafficLightWidth)
                        Spacer()
                    }

                    Button {
                        withAnimation(.easeOut(duration: Duration.fast)) {
                            appState.showCommandPalette = true
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: IconSize.xs))
                                .foregroundStyle(colors.mutedForeground)

                            Text("Search...")
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)

                            Spacer()

                            Text("⌘K")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(colors.mutedForeground.opacity(0.7))
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(colors.muted)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                        }
                        .frame(width: 200)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(colors.muted.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .stroke(colors.border.opacity(0.3), lineWidth: BorderWidth.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, Spacing.lg)
            }, height: titlebarHeight)
        }
        .background(colors.background)
        .background(WindowTitlebarConfigurator())
        .ignoresSafeArea(.container, edges: .top)
    }
}

#Preview {
    WorkspaceView()
        .environment(MockAppState())
        .frame(width: 1200, height: 800)
}
