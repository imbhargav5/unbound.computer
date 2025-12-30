//
//  VersionControlPanel.swift
//  rocketry-macos
//
//  Shadcn-styled version control panel
//

import SwiftUI

struct VersionControlPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var fileTree: [FileItem]
    @Binding var selectedTab: VersionControlTab
    @Binding var selectedTerminalTab: TerminalTab
    let workingDirectory: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VSplitView {
            // Top section - File tree with header
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Version control")
                        .font(Typography.h4)
                        .foregroundStyle(colors.foreground)

                    Spacer()

                    // Action buttons
                    HStack(spacing: Spacing.sm) {
                        IconButton(systemName: "arrow.triangle.2.circlepath", action: {})
                        IconButton(systemName: "magnifyingglass", action: {})
                        IconButton(systemName: "line.3.horizontal.decrease", action: {})
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                // Tab selector
                HStack {
                    SegmentedTabPicker(
                        selection: $selectedTab,
                        options: VersionControlTab.allCases
                    )

                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)

                ShadcnDivider()

                // File tree
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach($fileTree) { $item in
                            FileTreeRowSimple(item: $item, level: 0)
                        }
                    }
                    .padding(.top, Spacing.sm)
                }
            }
            .frame(minHeight: 150)

            // Bottom section - Terminal
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

                // SwiftTerm terminal
                if let path = workingDirectory {
                    TerminalContainer(workingDirectory: path)
                } else {
                    Text("No workspace selected")
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 100)
        }
        .background(colors.background)
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

#Preview {
    VersionControlPanel(
        fileTree: .constant(FakeData.fileTree),
        selectedTab: .constant(.allFiles),
        selectedTerminalTab: .constant(.terminal),
        workingDirectory: "/Users/test/project"
    )
    .frame(width: 280, height: 600)
}
