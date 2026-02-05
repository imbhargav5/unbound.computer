//
//  RightSidebarPanel.swift
//  unbound-macos
//
//  Main right sidebar panel with Changes, Files, and Commits tabs.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui.sidebar")

// MARK: - Editor Mode

enum EditorMode: String, CaseIterable, Identifiable, Hashable {
    case agent = "Agent"
    case editor = "Editor"

    var id: String { rawValue }
}

// MARK: - Editor Mode Toggle

struct EditorModeToggle: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selection: EditorMode

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditorMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(Typography.toolbar)
                        .foregroundStyle(selection == mode ? colors.foreground : colors.mutedForeground)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            selection == mode ?
                            colors.selectionBackground :
                            Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.xxs)
        .background(colors.muted)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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

    // Editor mode state
    @State private var selectedEditorMode: EditorMode = .agent

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var effectiveTab: RightSidebarTab {
        selectedTab == .spec ? .changes : selectedTab
    }

    private var bottomTabs: [RightSidebarTab] {
        [.changes, .files, .commits]
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

            // Agent Mode / Editor Mode toggle on the right
            EditorModeToggle(selection: $selectedEditorMode)
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
