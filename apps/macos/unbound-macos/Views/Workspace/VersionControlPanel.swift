//
//  VersionControlPanel.swift
//  unbound-macos
//
//  Shadcn-styled version control panel
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct VersionControlPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    /// ViewModel for file tree state (optional for preview compatibility)
    var viewModel: FileTreeViewModel?
    @Binding var selectedTab: VersionControlTab
    let workingDirectory: String?

    // Diff viewing state
    @State private var selectedFileDiff: FileDiff?
    @State private var isLoadingDiff: Bool = false
    @State private var showDiffPanel: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Get the appropriate file tree based on selected tab
    private var fileTree: [FileItem] {
        guard let viewModel = viewModel else { return [] }
        return selectedTab == .changes ? viewModel.changesTree : viewModel.allFilesTree
    }

    /// Get the selected file from ViewModel
    private var selectedFile: FileItem? {
        viewModel?.selectedFileItem
    }

    var body: some View {
        VSplitView {
            // Top section - File tree with header
            VStack(spacing: 0) {
                // Compact header with inline tabs
                HStack(spacing: Spacing.sm) {
                    // Tab buttons (inline text style)
                    Button {
                        selectedTab = .changes
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("Changes")
                                .font(Typography.bodySmall)
                                .fontWeight(selectedTab == .changes ? .semibold : .regular)
                                .foregroundStyle(selectedTab == .changes ? colors.foreground : colors.mutedForeground)

                            // Count badge
                            if let count = viewModel?.changesCount, count > 0 {
                                Text("\(count)")
                                    .font(Typography.micro)
                                    .foregroundStyle(colors.mutedForeground)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(colors.muted)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedTab = .allFiles
                    } label: {
                        Text("All files")
                            .font(Typography.bodySmall)
                            .fontWeight(selectedTab == .allFiles ? .semibold : .regular)
                            .foregroundStyle(selectedTab == .allFiles ? colors.foreground : colors.mutedForeground)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Action buttons
                    HStack(spacing: Spacing.xs) {
                        IconButton(systemName: "arrow.triangle.2.circlepath", action: {
                            Task { await refreshStatus() }
                        })
                        IconButton(systemName: "magnifyingglass", action: {})
                        IconButton(systemName: "line.3.horizontal.decrease", action: {})
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)

                ShadcnDivider()

                // File tree
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(fileTree) { item in
                            FileTreeRowWithViewModel(
                                item: item,
                                level: 0,
                                viewModel: viewModel,
                                onFileSelected: { file in
                                    selectFile(file)
                                }
                            )
                        }
                    }
                }
            }
            .frame(minHeight: 150)

            // Middle section - Diff viewer (if file selected)
            if showDiffPanel {
                VStack(spacing: 0) {
                    ShadcnDivider()

                    // Diff header
                    HStack {
                        if let file = selectedFile {
                            Image(systemName: "doc.text")
                                .font(.system(size: IconSize.sm))
                                .foregroundStyle(colors.mutedForeground)

                            Text(file.name)
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
                                viewModel?.clearSelection()
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

        }
        .background(colors.background)
    }

    // MARK: - Actions

    private func selectFile(_ file: FileItem) {
        guard file.type == .file else { return }

        viewModel?.selectFile(file.id)
        showDiffPanel = true

        Task {
            await loadDiffForFile(file)
        }
    }

    private func loadDiffForFile(_ file: FileItem) async {
        guard let path = workingDirectory else { return }

        isLoadingDiff = true
        defer { isLoadingDiff = false }

        // TODO: Load diff from daemon via git.diff_file
        // For now, skip diff loading
        logger.debug("Diff loading not yet implemented with daemon")
        selectedFileDiff = nil
    }

    private func refreshStatus() async {
        // This would trigger a refresh of the file tree
        // The parent view (WorkspaceView) owns the file tree state
    }
}

// MARK: - Simple File Tree Row

struct FileTreeRowSimple: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var item: FileItem
    let level: Int

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.hasChildren {
                    withAnimation(.easeInOut(duration: Duration.default)) {
                        item.isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if item.hasChildren {
                        Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.xs)
                    } else {
                        Color.clear
                            .frame(width: IconSize.xs)
                    }

                    Image(systemName: item.type.iconName)
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(item.type.iconColor)

                    Text(item.name)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    Spacer()

                    // Git status indicator
                    if item.gitStatus != .unchanged {
                        Text(item.gitStatus.indicator)
                            .font(Typography.micro)
                            .foregroundStyle(item.gitStatus.color)
                            .padding(.trailing, Spacing.xs)
                    }
                }
                .padding(.leading, CGFloat(level) * Spacing.lg + Spacing.md)
                .padding(.trailing, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()

            if item.isExpanded && item.hasChildren {
                ForEach($item.children) { $child in
                    FileTreeRowSimple(item: $child, level: level + 1)
                }
            }
        }
    }
}

// MARK: - File Tree Row With ViewModel Support

struct FileTreeRowWithViewModel: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: FileItem
    let level: Int
    var viewModel: FileTreeViewModel?
    var onFileSelected: (FileItem) -> Void

    @State private var isHovered: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var isSelected: Bool {
        viewModel?.selectedFileId == item.id
    }

    private var isExpanded: Bool {
        viewModel?.isExpanded(item.id) ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.hasChildren {
                    withAnimation(.easeInOut(duration: Duration.default)) {
                        viewModel?.toggleExpanded(item.id)
                    }
                } else if item.type == .file && item.gitStatus != .unchanged {
                    // Only select files with changes
                    onFileSelected(item)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if item.hasChildren {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.xs)
                    } else {
                        Color.clear
                            .frame(width: IconSize.xs)
                    }

                    Image(systemName: item.type.iconName)
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(item.type.iconColor)

                    Text(item.name)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    Spacer()

                    // Git status indicator
                    if item.gitStatus != .unchanged {
                        Text(item.gitStatus.indicator)
                            .font(Typography.micro)
                            .foregroundStyle(item.gitStatus.color)
                            .padding(.trailing, Spacing.xs)
                    }
                }
                .padding(.leading, CGFloat(level) * Spacing.lg + Spacing.md)
                .padding(.trailing, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }

            if isExpanded && item.hasChildren {
                ForEach(item.children) { child in
                    FileTreeRowWithViewModel(
                        item: child,
                        level: level + 1,
                        viewModel: viewModel,
                        onFileSelected: onFileSelected
                    )
                }
            }
        }
    }
}

// MARK: - File Tree Row With Diff Support (Legacy - uses Binding)

struct FileTreeRowWithDiff: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var item: FileItem
    let level: Int
    @Binding var selectedFile: FileItem?
    var onFileSelected: (FileItem) -> Void

    @State private var isHovered: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var isSelected: Bool {
        selectedFile?.id == item.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.hasChildren {
                    withAnimation(.easeInOut(duration: Duration.default)) {
                        item.isExpanded.toggle()
                    }
                } else if item.type == .file && item.gitStatus != .unchanged {
                    // Only select files with changes
                    onFileSelected(item)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if item.hasChildren {
                        Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.xs)
                    } else {
                        Color.clear
                            .frame(width: IconSize.xs)
                    }

                    Image(systemName: item.type.iconName)
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(item.type.iconColor)

                    Text(item.name)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    Spacer()

                    // Git status indicator
                    if item.gitStatus != .unchanged {
                        Text(item.gitStatus.indicator)
                            .font(Typography.micro)
                            .foregroundStyle(item.gitStatus.color)
                            .padding(.trailing, Spacing.xs)
                    }
                }
                .padding(.leading, CGFloat(level) * Spacing.lg + Spacing.md)
                .padding(.trailing, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }

            if item.isExpanded && item.hasChildren {
                ForEach($item.children) { $child in
                    FileTreeRowWithDiff(
                        item: $child,
                        level: level + 1,
                        selectedFile: $selectedFile,
                        onFileSelected: onFileSelected
                    )
                }
            }
        }
    }
}

#Preview {
    VersionControlPanel(
        viewModel: nil,
        selectedTab: .constant(.allFiles),
        workingDirectory: "/Users/test/project"
    )
    .frame(width: 280, height: 600)
}
