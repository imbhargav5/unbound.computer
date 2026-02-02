//
//  RightSidebarPanel.swift
//  mockup-macos
//
//  Main right sidebar panel with Changes, Files, and Commits tabs.
//

import SwiftUI

// MARK: - Right Sidebar Tab

enum RightSidebarTab: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case files = "Files"
    case commits = "Commits"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .changes: return "arrow.triangle.2.circlepath"
        case .files: return "folder"
        case .commits: return "clock"
        }
    }
}

// MARK: - Terminal Tab

enum TerminalTab: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case output = "Output"
    case problems = "Problems"

    var id: String { rawValue }
}

struct RightSidebarPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MockAppState.self) private var appState

    // State bindings
    @Binding var selectedTab: RightSidebarTab
    @Binding var selectedTerminalTab: TerminalTab

    // Working directory
    let workingDirectory: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VSplitView {
            // Top section - Tab content
            VStack(spacing: 0) {
                // Tab header
                tabHeader

                ShadcnDivider()

                // Tab content
                tabContent
            }
            .frame(minHeight: 150)

            // Bottom section - Terminal
            terminalSection
        }
        .background(colors.background)
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
                        if tab == .changes {
                            Text("\(FakeData.changedFiles.count)")
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

            // Refresh button
            IconButton(systemName: "arrow.triangle.2.circlepath", action: {})
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .changes:
            ChangesTabView()
        case .files:
            FilesTabView()
        case .commits:
            CommitsTabView()
        }
    }

    // MARK: - Terminal Section

    private var terminalSection: some View {
        VStack(spacing: 0) {
            ShadcnDivider()

            // Terminal tabs header
            HStack(spacing: 0) {
                ForEach(TerminalTab.allCases) { tab in
                    Button {
                        selectedTerminalTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(Typography.bodySmall)
                            .foregroundStyle(selectedTerminalTab == tab ? colors.foreground : colors.mutedForeground)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.plain)
                }

                IconButton(systemName: "plus", size: IconSize.xs, action: {})

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            ShadcnDivider()

            // Terminal content (mock)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("$ ")
                    .font(Typography.terminal)
                    .foregroundStyle(colors.success)
                +
                Text("Ready")
                    .font(Typography.terminal)
                    .foregroundStyle(colors.foreground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
            .background(colors.card)
        }
        .frame(minHeight: 100)
    }
}

// MARK: - Changes Tab View

/// Redesigned Changes view with Git-standard visual language.
/// Design principles:
/// - Status visible at a glance (<200ms recognition)
/// - Git-standard indicators: M, A, D, R, ?
/// - Color coding: Green=Added, Yellow=Modified, Red=Deleted, Gray=Untracked
/// - Grouped by status with clear section headers
struct ChangesTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var stagedExpanded = true
    @State private var changesExpanded = true
    @State private var untrackedExpanded = true
    @State private var selectedFileId: UUID?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    // Group files by status category
    private var modifiedFiles: [GitStatusFile] {
        FakeData.changedFiles.filter { $0.status == .modified }
    }

    private var addedFiles: [GitStatusFile] {
        FakeData.changedFiles.filter { $0.status == .added }
    }

    private var deletedFiles: [GitStatusFile] {
        FakeData.changedFiles.filter { $0.status == .deleted }
    }

    private var untrackedFiles: [GitStatusFile] {
        FakeData.changedFiles.filter { $0.status == .untracked }
    }

    private var trackedChanges: [GitStatusFile] {
        FakeData.changedFiles.filter { $0.status != .untracked }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Summary header showing total changes
                changesSummaryHeader

                ShadcnDivider()

                // Changes section (modified, added, deleted)
                if !trackedChanges.isEmpty {
                    ChangesSection(
                        title: "Changes",
                        count: trackedChanges.count,
                        isExpanded: $changesExpanded,
                        statusSummary: statusBreakdown(trackedChanges)
                    ) {
                        ForEach(trackedChanges) { file in
                            ChangeFileRow(
                                file: file,
                                isSelected: selectedFileId == file.id,
                                onSelect: { selectedFileId = file.id }
                            )
                        }
                    }
                }

                // Untracked section
                if !untrackedFiles.isEmpty {
                    ChangesSection(
                        title: "Untracked",
                        count: untrackedFiles.count,
                        isExpanded: $untrackedExpanded
                    ) {
                        ForEach(untrackedFiles) { file in
                            ChangeFileRow(
                                file: file,
                                isSelected: selectedFileId == file.id,
                                onSelect: { selectedFileId = file.id }
                            )
                        }
                    }
                }

                // Empty state
                if FakeData.changedFiles.isEmpty {
                    emptyState
                }
            }
        }
    }

    // MARK: - Summary Header

    @ViewBuilder
    private var changesSummaryHeader: some View {
        HStack(spacing: Spacing.md) {
            // Status counts with colors
            if !modifiedFiles.isEmpty {
                statusCount(count: modifiedFiles.count, indicator: "M", color: colors.warning)
            }
            if !addedFiles.isEmpty {
                statusCount(count: addedFiles.count, indicator: "A", color: colors.success)
            }
            if !deletedFiles.isEmpty {
                statusCount(count: deletedFiles.count, indicator: "D", color: colors.destructive)
            }
            if !untrackedFiles.isEmpty {
                statusCount(count: untrackedFiles.count, indicator: "?", color: colors.mutedForeground)
            }

            Spacer()

            // Total files changed
            Text("\(FakeData.changedFiles.count) files")
                .font(Typography.micro)
                .foregroundStyle(colors.mutedForeground)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private func statusCount(count: Int, indicator: String, color: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            Text("\(count)")
                .font(.system(size: FontSize.xs, weight: .semibold, design: .monospaced))
            Text(indicator)
                .font(.system(size: FontSize.xs, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
    }

    private func statusBreakdown(_ files: [GitStatusFile]) -> [FileStatus: Int] {
        var breakdown: [FileStatus: Int] = [:]
        for file in files {
            breakdown[file.status, default: 0] += 1
        }
        return breakdown
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: IconSize.xxxl))
                .foregroundStyle(colors.success)

            Text("Working directory clean")
                .font(Typography.body)
                .foregroundStyle(colors.foreground)

            Text("No uncommitted changes")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Changes Section

/// Collapsible section for grouping files
struct ChangesSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    var statusSummary: [FileStatus: Int]?
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: Duration.fast)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    // Chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: IconSize.xs, weight: .semibold))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: IconSize.sm)

                    // Title
                    Text(title)
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.mutedForeground)
                        .textCase(.uppercase)

                    // Count badge
                    Text("\(count)")
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(colors.muted)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                    // Status breakdown
                    if let summary = statusSummary {
                        statusBreakdownView(summary)
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                content()
            }
        }
    }

    @ViewBuilder
    private func statusBreakdownView(_ summary: [FileStatus: Int]) -> some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(summary.keys.sorted { $0.rawValue < $1.rawValue }), id: \.self) { status in
                if let statusCount = summary[status], statusCount > 0 {
                    HStack(spacing: 1) {
                        Text("\(statusCount)")
                            .font(.system(size: FontSize.xxs, weight: .medium, design: .monospaced))
                        Text(status.indicator)
                            .font(.system(size: FontSize.xxs, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(statusColor(for: status))
                }
            }
        }
    }

    private func statusColor(for status: FileStatus) -> Color {
        switch status {
        case .added: return colors.success
        case .modified: return colors.warning
        case .deleted: return colors.destructive
        case .renamed: return colors.info
        case .untracked: return colors.mutedForeground
        }
    }
}

// MARK: - Change File Row

/// A single file row with Git-standard status indicator.
/// Design: [M] filename.swift
///              path/to/file/
struct ChangeFileRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let file: GitStatusFile
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Status badge with letter indicator
                statusBadge

                // File info
                VStack(alignment: .leading, spacing: 0) {
                    Text(file.filename)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    // Directory path (if available)
                    let directory = file.path.replacingOccurrences(of: file.filename, with: "")
                    if !directory.isEmpty {
                        Text(directory)
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Hover actions
                if isHovered {
                    HStack(spacing: Spacing.xs) {
                        IconButton(
                            systemName: "plus.circle",
                            size: IconSize.sm,
                            action: {}
                        )
                        .help("Stage")
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        let statusColor = semanticStatusColor

        Text(file.status.indicator)
            .font(.system(size: FontSize.xs, weight: .semibold, design: .monospaced))
            .foregroundStyle(statusColor)
            .frame(width: IconSize.lg, height: IconSize.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(statusColor.opacity(0.15))
            )
    }

    private var semanticStatusColor: Color {
        switch file.status {
        case .added: return colors.success
        case .modified: return colors.warning
        case .deleted: return colors.destructive
        case .renamed: return colors.info
        case .untracked: return colors.mutedForeground
        }
    }
}

// MARK: - Files Tab View

struct FilesTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(FakeData.fileTree) { item in
                    FileTreeRow(item: item, level: 0)
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }
}

// MARK: - File Tree Row

struct FileTreeRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: FileItem
    let level: Int

    @State private var isExpanded: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.isDirectory {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if item.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.xs)
                    } else {
                        Spacer()
                            .frame(width: IconSize.xs)
                    }

                    Image(systemName: item.iconName)
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(item.isDirectory ? colors.info : colors.mutedForeground)

                    Text(item.name)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.leading, CGFloat(level) * Spacing.lg + Spacing.md)
                .padding(.trailing, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileTreeRow(item: child, level: level + 1)
                }
            }
        }
    }
}

// MARK: - Commits Tab View (Timeline)

struct CommitsTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedCommitId: UUID?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(FakeData.commits.enumerated()), id: \.element.id) { index, commit in
                    CommitTimelineRow(
                        commit: commit,
                        index: index,
                        totalCount: FakeData.commits.count,
                        isSelected: selectedCommitId == commit.id,
                        isFirst: index == 0,
                        isLast: index == FakeData.commits.count - 1,
                        onSelect: {
                            selectedCommitId = commit.id
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Timeline Constants

private enum TimelineConstants {
    static let columnWidth: CGFloat = 28
    static let lineWidth: CGFloat = 1.5
    static let nodeRadius: CGFloat = 4
    static let nodeStrokeWidth: CGFloat = 1.5
    static let rowHeight: CGFloat = 52
}

// MARK: - Commit Timeline Row

private struct CommitTimelineRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let commit: GitCommit
    let index: Int
    let totalCount: Int
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Progressive opacity fade for older commits
    private var temporalOpacity: Double {
        if index == 0 { return 1.0 }
        let fadeStart = 0.85
        let fadeEnd = 0.5
        let fadeRange = min(Double(index) / 20.0, 1.0)
        return fadeStart - (fadeStart - fadeEnd) * fadeRange
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 0) {
                // Timeline node column
                TimelineNode(
                    isFirst: isFirst,
                    isLast: isLast,
                    isSelected: isSelected,
                    isHovered: isHovered
                )
                .frame(width: TimelineConstants.columnWidth)
                .frame(height: TimelineConstants.rowHeight)

                // Commit content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    // Commit message (primary)
                    Text(commit.message)
                        .font(Typography.bodySmall)
                        .fontWeight(isFirst ? .medium : .regular)
                        .foregroundStyle(colors.foreground.opacity(temporalOpacity))
                        .lineLimit(1)

                    // Metadata row
                    HStack(spacing: Spacing.sm) {
                        // Short hash (monospace)
                        Text(commit.shortHash)
                            .font(Typography.mono)
                            .foregroundStyle(colors.info.opacity(temporalOpacity))

                        // Relative time
                        Text(formatDate(commit.date))
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground.opacity(temporalOpacity))

                        Spacer()

                        // Author (de-emphasized, shows on hover or for first commit)
                        if isFirst || isHovered {
                            Text(commit.author)
                                .font(Typography.micro)
                                .foregroundStyle(colors.mutedForeground.opacity(temporalOpacity * 0.8))
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                }
                .padding(.vertical, Spacing.sm)
                .padding(.trailing, Spacing.md)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(backgroundColor)
                    .padding(.leading, TimelineConstants.columnWidth - Spacing.xs)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return colors.accent
        } else if isHovered {
            return colors.muted.opacity(0.5)
        }
        return Color.clear
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Timeline Node

private struct TimelineNode: View {
    @Environment(\.colorScheme) private var colorScheme

    let isFirst: Bool
    let isLast: Bool
    let isSelected: Bool
    let isHovered: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var lineColor: Color {
        colors.mutedForeground.opacity(0.3)
    }

    private var nodeColor: Color {
        if isFirst {
            return colors.success
        }
        return colors.mutedForeground.opacity(0.6)
    }

    var body: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            let centerY = size.height / 2

            // Draw vertical line (above node)
            if !isFirst {
                var pathAbove = Path()
                pathAbove.move(to: CGPoint(x: centerX, y: 0))
                pathAbove.addLine(to: CGPoint(x: centerX, y: centerY - TimelineConstants.nodeRadius - 2))
                context.stroke(pathAbove, with: .color(lineColor), lineWidth: TimelineConstants.lineWidth)
            }

            // Draw vertical line (below node)
            if !isLast {
                var pathBelow = Path()
                pathBelow.move(to: CGPoint(x: centerX, y: centerY + TimelineConstants.nodeRadius + 2))
                pathBelow.addLine(to: CGPoint(x: centerX, y: size.height))
                context.stroke(pathBelow, with: .color(lineColor), lineWidth: TimelineConstants.lineWidth)
            }

            // Draw node circle
            let nodeRect = CGRect(
                x: centerX - TimelineConstants.nodeRadius,
                y: centerY - TimelineConstants.nodeRadius,
                width: TimelineConstants.nodeRadius * 2,
                height: TimelineConstants.nodeRadius * 2
            )

            if isFirst {
                // Filled circle for HEAD/newest
                context.fill(Circle().path(in: nodeRect), with: .color(nodeColor))
            } else {
                // Outlined circle for history
                context.stroke(
                    Circle().path(in: nodeRect),
                    with: .color(nodeColor),
                    lineWidth: TimelineConstants.nodeStrokeWidth
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    RightSidebarPanel(
        selectedTab: .constant(.changes),
        selectedTerminalTab: .constant(.terminal),
        workingDirectory: "/Users/test/project"
    )
    .environment(MockAppState())
    .frame(width: 300, height: 600)
}
