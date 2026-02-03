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
                        .font(Typography.bodySmall)
                        .foregroundStyle(selection == mode ? colors.foreground : colors.mutedForeground)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            selection == mode ?
                            colors.card :
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

    var body: some View {
        VSplitView {
            // Top section - Tab content
            VStack(spacing: 0) {
                // Top toolbar row (matches main content area top bar height)
                topToolbarRow

                ShadcnDivider()

                // Tab header
                tabHeader

                ShadcnDivider()

                // Tab content
                tabContent
            }
            .frame(minHeight: 150)

            // Footer (empty, 20px height)
            ShadcnDivider()

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
                .font(Typography.bodySmall)
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
        .frame(height: 40)
        .background(colors.card)
    }

    // MARK: - Tab Header

    private var tabHeader: some View {
        HStack(spacing: Spacing.sm) {
            // Tab buttons
            ForEach(RightSidebarTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: IconSize.xs))

                        Text(tab.rawValue)
                            .font(Typography.bodySmall)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)

                        // Badge for changes count
                        if tab == .changes, gitViewModel.changesCount > 0 {
                            Text("\(gitViewModel.changesCount)")
                                .font(Typography.micro)
                                .foregroundStyle(colors.mutedForeground)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.xxs)
                                .background(colors.muted)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? colors.foreground : colors.mutedForeground)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Action buttons
            HStack(spacing: Spacing.xs) {
                IconButton(systemName: "arrow.triangle.2.circlepath", action: {
                    Task { await gitViewModel.refreshAll() }
                })
            }
        }
        .padding(.horizontal, Spacing.compact)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
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
        // Avoid loading file contents on click to keep UI responsive.
        // File content can be opened via explicit action later.
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
