//
//  SidebarComponents.swift
//  mockup-macos
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

// MARK: - Session Icon

struct SessionIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let isActive: Bool
    let size: CGFloat

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ZStack {
            if isActive {
                // Animated loader when active
                Circle()
                    .stroke(colors.info.opacity(0.3), lineWidth: 2)
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(colors.info, lineWidth: 2)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isActive)
            } else {
                // Static icon when idle
                Image(systemName: "message")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(colors.mutedForeground)
            }
        }
        .frame(width: size, height: size)
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
