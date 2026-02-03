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

    // State bindings
    @Binding var selectedTab: RightSidebarTab

    // Working directory
    let workingDirectory: String?

    // Diff viewing state
    @State private var selectedFileDiff: FileDiff?
    @State private var isLoadingDiff: Bool = false
    @State private var showDiffPanel: Bool = false

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

            // Middle section - Diff viewer (if file selected)
            if showDiffPanel {
                diffPanel
            }

            // Footer (empty, 20px height)
            ShadcnDivider()

            Color.clear
                .frame(height: 20)
                .background(colors.card)
        }
        .background(colors.background)
        .onChange(of: workingDirectory) { _, newPath in
            Task {
                await gitViewModel.setRepository(path: newPath)
            }
        }
        .onAppear {
            gitViewModel.setDaemonClient(appState.daemonClient)
            Task {
                await gitViewModel.setRepository(path: workingDirectory)
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

    // MARK: - Diff Panel

    private var diffPanel: some View {
        VStack(spacing: 0) {
            ShadcnDivider()

            // Diff header
            HStack {
                if let path = gitViewModel.selectedFilePath {
                    Image(systemName: "doc.text")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)

                    Text((path as NSString).lastPathComponent)
                        .font(Typography.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.foreground)
                }

                Spacer()

                if isLoadingDiff {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                // Close button
                Button {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        showDiffPanel = false
                        gitViewModel.selectFile(nil)
                        selectedFileDiff = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            ShadcnDivider()

            // Diff content
            if let diff = selectedFileDiff {
                ScrollView {
                    if diff.isBinary {
                        BinaryDiffView()
                    } else if diff.hunks.isEmpty {
                        EmptyDiffView()
                    } else {
                        UnifiedDiffView(hunks: diff.hunks)
                    }
                }
            } else if !isLoadingDiff {
                Text("Select a file to view diff")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minHeight: 150, maxHeight: 300)
        .background(colors.card)
    }

    // MARK: - Actions

    private func selectFile(_ file: GitStatusFile) {
        gitViewModel.selectFile(file.path)
        showDiffPanel = true
        Task {
            await loadDiffForFile(file.path)
        }
    }

    private func selectFile(_ file: FileItem) {
        guard file.type == .file else { return }
        fileTreeViewModel?.selectFile(file.id)
        // For file tree, we'd need to get the path
        // This is a simplified version
        showDiffPanel = true
    }

    private func loadDiffForFile(_ path: String) async {
        guard let workDir = workingDirectory else { return }

        isLoadingDiff = true
        defer { isLoadingDiff = false }

        do {
            let diffContent = try await appState.daemonClient.getGitDiff(path: workDir, filePath: path)
            if !diffContent.isEmpty {
                selectedFileDiff = FileDiff.parse(from: diffContent, filePath: path)
            } else {
                selectedFileDiff = nil
            }
        } catch {
            logger.warning("Failed to load diff: \(error.localizedDescription)")
            selectedFileDiff = nil
        }
    }
}

// MARK: - Preview

#Preview {
    RightSidebarPanel(
        fileTreeViewModel: nil,
        gitViewModel: GitViewModel(),
        selectedTab: .constant(.changes),
        workingDirectory: "/Users/test/project"
    )
    .frame(width: 300, height: 600)
}
