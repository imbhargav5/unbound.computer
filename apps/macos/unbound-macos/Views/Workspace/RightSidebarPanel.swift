//
//  RightSidebarPanel.swift
//  unbound-macos
//
//  Main right sidebar panel with Changes, Files, and Commits tabs.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui.sidebar")

// MARK: - Git Toolbar Action

private enum GitToolbarAction: Hashable {
    case commit
    case push

    var title: String {
        switch self {
        case .commit:
            return "Commit"
        case .push:
            return "Push"
        }
    }

    var systemImage: String {
        switch self {
        case .commit:
            return "checkmark.circle.fill"
        case .push:
            return "arrow.up.circle.fill"
        }
    }
}

private struct GitToolbarActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: GitToolbarAction
    let onTap: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: action.systemImage)
                    .font(.system(size: IconSize.xs))
                Text(action.title)
                    .font(Typography.toolbar)
            }
            .foregroundStyle(colors.primaryActionForeground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(colors.primaryAction)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }
}

struct RightSidebarPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    // View models
    var fileTreeViewModel: FileTreeViewModel?
    @Bindable var gitViewModel: GitViewModel
    @Bindable var editorState: EditorState

    // State bindings
    @Binding var selectedTab: RightSidebarTab

    // Working directory
    let workingDirectory: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var effectiveTab: RightSidebarTab {
        selectedTab == .spec ? .changes : selectedTab
    }

    private var bottomTabs: [RightSidebarTab] {
        [.changes, .files, .commits]
    }

    private var currentLocalBranch: GitBranch? {
        if let currentName = gitViewModel.currentBranch,
           let branch = gitViewModel.localBranches.first(where: { $0.name == currentName }) {
            return branch
        }
        return gitViewModel.localBranches.first(where: { $0.isCurrent })
    }

    private var gitToolbarAction: GitToolbarAction? {
        if gitViewModel.changesCount > 0 {
            return .commit
        }
        if let branch = currentLocalBranch,
           branch.upstream != nil,
           branch.ahead > 0 {
            return .push
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topToolbarRow

            ShadcnDivider()

            VSplitView {
                // Top section - Spec/Tasks panel
                VStack(spacing: 0) {
                    SpecTasksTabView()
                }
                .frame(minHeight: 220)
                .background(colors.background)

                // Bottom section - Changes/Files/Commits
                VStack(spacing: 0) {
                    changesHeader
                    ShadcnDivider()
                    bottomTabHeader
                    ShadcnDivider()
                    bottomTabContent
                }
                .frame(minHeight: 200)
            }

            ShadcnDivider()

            // Footer (empty, 20px height)
            Color.clear
                .frame(height: 20)
                .background(colors.card)
        }
        .background(colors.background)
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .files {
                Task { await fileTreeViewModel?.loadRoot() }
            }
        }
        .onChange(of: workingDirectory) { _, newPath in
            Task {
                await gitViewModel.setRepository(path: newPath)
            }
        }
        .onAppear {
            gitViewModel.setDaemonClient(appState.daemonClient)
            if selectedTab == .spec {
                selectedTab = .changes
            }
            Task {
                await gitViewModel.setRepository(path: workingDirectory)
                if selectedTab == .files {
                    await fileTreeViewModel?.loadRoot()
                }
            }
        }
    }

    // MARK: - Top Toolbar Row

    private var topToolbarRow: some View {
        HStack(spacing: Spacing.md) {
            // Open selector on the left
            Button(action: {
                // Open action placeholder
            }) {
                HStack(spacing: Spacing.xs) {
                    Text("Open")
                    Image(systemName: "chevron.down")
                        .font(.system(size: IconSize.xs))
                }
                .font(Typography.toolbar)
                .foregroundStyle(colors.mutedForeground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)

            Spacer()

            if let action = gitToolbarAction {
                GitToolbarActionButton(action: action, onTap: {})
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: LayoutMetrics.toolbarHeight)
        .background(colors.toolbarBackground)
    }

    // MARK: - Changes Header

    private var changesHeader: some View {
        HStack(spacing: Spacing.sm) {
            Text("Changes")
                .font(Typography.toolbar)
                .foregroundStyle(colors.foreground)

            if gitViewModel.changesCount > 0 {
                Text("\(gitViewModel.changesCount)")
                    .font(Typography.micro)
                    .foregroundStyle(colors.mutedForeground)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(colors.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .stroke(colors.border, lineWidth: BorderWidth.hairline)
                    )
            }

            Spacer()

            IconButton(systemName: "arrow.triangle.2.circlepath", action: {
                Task { await gitViewModel.refreshAll() }
            })
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: LayoutMetrics.toolbarHeight)
        .background(colors.toolbarBackground)
    }

    // MARK: - Bottom Tab Header

    private var bottomTabHeader: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(bottomTabs) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: IconSize.xs))

                        Text(tab.rawValue)
                            .font(Typography.toolbarMuted)
                            .fontWeight(effectiveTab == tab ? .semibold : .regular)
                    }
                    .foregroundStyle(effectiveTab == tab ? colors.foreground : colors.mutedForeground)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .background(colors.background)
    }

    // MARK: - Bottom Tab Content

    @ViewBuilder
    private var bottomTabContent: some View {
        switch effectiveTab {
        case .changes:
            ChangesTabView(
                gitViewModel: gitViewModel,
                onFileSelected: { file in
                    selectFile(file)
                }
            )
        case .files:
            FilesTabView(
                fileTreeViewModel: fileTreeViewModel,
                onFileSelected: { file in
                    selectFile(file)
                }
            )
        case .commits:
            CommitsTabView(gitViewModel: gitViewModel)
        case .spec:
            ChangesTabView(
                gitViewModel: gitViewModel,
                onFileSelected: { file in
                    selectFile(file)
                }
            )
        }
    }

    // MARK: - Actions

    private func selectFile(_ file: GitStatusFile) {
        gitViewModel.selectFile(file.path)
        editorState.openDiffTab(relativePath: file.path)
        Task {
            await loadDiffForFile(file.path)
        }
    }

    private func selectFile(_ file: FileItem) {
        guard !file.isDirectory else { return }
        fileTreeViewModel?.selectFile(file.path)
        if let fullPath = resolveFullPath(for: file) {
            editorState.openFileTab(
                relativePath: file.path,
                fullPath: fullPath,
                sessionId: appState.selectedSessionId
            )
        }
    }

    private func resolveFullPath(for file: FileItem) -> String? {
        if file.path.hasPrefix("/") {
            return file.path
        }
        guard let workDir = workingDirectory else { return nil }
        return URL(fileURLWithPath: workDir).appendingPathComponent(file.path).path
    }

    private func loadDiffForFile(_ path: String) async {
        guard let workDir = workingDirectory else { return }

        editorState.setDiffLoading(for: path, isLoading: true)
        defer { editorState.setDiffLoading(for: path, isLoading: false) }

        do {
            let diffContent = try await appState.daemonClient.getGitDiff(path: workDir, filePath: path)
            if !diffContent.isEmpty {
                editorState.setDiff(for: path, diff: FileDiff.parse(from: diffContent, filePath: path))
            } else {
                editorState.setDiff(for: path, diff: nil)
            }
        } catch {
            logger.warning("Failed to load diff: \(error.localizedDescription)")
            editorState.setDiffError(for: path, message: error.localizedDescription)
        }
    }
}

// MARK: - Preview

#Preview {
    RightSidebarPanel(
        fileTreeViewModel: nil,
        gitViewModel: GitViewModel(),
        editorState: EditorState(),
        selectedTab: .constant(.changes),
        workingDirectory: "/Users/test/project"
    )
    .frame(width: 300, height: 600)
}
