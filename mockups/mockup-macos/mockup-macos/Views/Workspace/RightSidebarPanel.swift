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

struct ChangesTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(FakeData.changedFiles) { file in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: file.status.iconName)
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(statusColor(for: file.status))

                        Text(file.filename)
                            .font(Typography.bodySmall)
                            .foregroundStyle(colors.foreground)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(Color.clear)
                    )
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }

    private func statusColor(for status: FileStatus) -> Color {
        switch status {
        case .modified: return colors.warning
        case .added: return colors.success
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

// MARK: - Commits Tab View

struct CommitsTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(FakeData.commits) { commit in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            Text(commit.shortHash)
                                .font(Typography.mono)
                                .foregroundStyle(colors.info)

                            Text(commit.message)
                                .font(Typography.bodySmall)
                                .foregroundStyle(colors.foreground)
                                .lineLimit(1)
                        }

                        HStack(spacing: Spacing.sm) {
                            Text(commit.author)
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)

                            Text(formatDate(commit.date))
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
