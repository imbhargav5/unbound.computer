//
//  SidebarComponents.swift
//  rocketry-macos
//
//  Shadcn-styled sidebar components
//

import SwiftUI

// MARK: - Sidebar Header

struct SidebarHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var action: (() -> Void)?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack {
            Text(title)
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Spacer()

            if let action = action {
                Button(action: action) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                }
                .buttonGhost(size: .icon)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Expandable Group

struct ExpandableGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: Duration.default)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: IconSize.xs, weight: .semibold))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: Spacing.md)

                    Text(title)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)

                    Spacer()

                    Image(systemName: "ellipsis")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()

            if isExpanded {
                content()
                    .padding(.leading, Spacing.sm)
            }
        }
    }
}

// MARK: - Repository Row

struct RepositoryRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
    let isSelected: Bool
    var onSelect: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(colors.mutedForeground)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(repository.name)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text(repository.branchName)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)

                        if !repository.lastUpdated.isEmpty {
                            Text("  \(repository.lastUpdated)")
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground.opacity(0.7))
                        }
                    }
                }

                Spacer()

                if let shortcut = repository.keyboardShortcut {
                    Text(shortcut)
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                        .background(colors.muted)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .selectionStyle(isSelected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Branch Row

struct BranchRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let branch: Branch

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: branch.type.iconName)
                .font(.system(size: IconSize.xs))
                .foregroundStyle(colors.mutedForeground)

            Text(branch.name)
                .font(Typography.caption)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)

            if !branch.statsText.isEmpty {
                HStack(spacing: 0) {
                    Text("+\(branch.additions)")
                        .font(Typography.micro)
                        .foregroundStyle(colors.success)
                    Text(" -\(branch.deletions)")
                        .font(Typography.micro)
                        .foregroundStyle(colors.destructive)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }

            if branch.isArchived {
                Badge("Archive", variant: .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - New Workspace Button

struct NewWorkspaceButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var action: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: IconSize.sm))
                Text("New workspace")
                    .font(Typography.bodySmall)
            }
            .foregroundStyle(colors.mutedForeground)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}

// MARK: - Add Repository Button

struct AddRepositoryButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var action: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: IconSize.md))
                Text("Add repository")
                    .font(Typography.bodySmall)
            }
            .foregroundStyle(colors.mutedForeground)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar Footer

struct SidebarFooter: View {
    @Environment(\.colorScheme) private var colorScheme

    var onAddRepository: () -> Void
    var onOpenSettings: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack {
            AddRepositoryButton(action: onAddRepository)

            Spacer()

            HStack(spacing: Spacing.md) {
                IconButton(systemName: "message", action: {})

                IconButton(systemName: "gearshape", action: onOpenSettings)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Create Worktree Button

struct CreateWorktreeButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let isLoading: Bool
    var action: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: IconSize.sm, height: IconSize.sm)
                } else {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: IconSize.sm))
                }
                Text(isLoading ? "Creating..." : "Create Worktree")
                    .font(Typography.bodySmall)
            }
            .foregroundStyle(colors.primary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .hoverEffect()
    }
}

// MARK: - Workspace Git Info Row

struct WorkspaceGitInfoRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let branch: String
    let isClean: Bool
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(colors.mutedForeground)

                Text(branch)
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)

                Spacer()

                // Clean/dirty indicator
                Circle()
                    .fill(isClean ? colors.success : colors.warning)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
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
}
