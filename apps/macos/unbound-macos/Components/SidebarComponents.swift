//
//  SidebarComponents.swift
//  unbound-macos
//
//  Shadcn-styled sidebar components
//

import SwiftUI

// MARK: - Sidebar Header

struct SidebarHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var onOpenKeyboardShortcuts: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    @State private var showMenu = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(colors.success)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(Typography.sidebarHeader)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(colors.mutedForeground)
            }

            Spacer()

            if onOpenKeyboardShortcuts != nil || onOpenSettings != nil {
                Button {
                    showMenu = true
                } label: {
                    let iconSize = LayoutMetrics.toolbarIconHitSize - (Spacing.xs * 2)
                    Image(systemName: "ellipsis")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: iconSize, height: iconSize, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonGhost(size: .icon)
                .popover(isPresented: $showMenu, arrowEdge: .trailing) {
                    SidebarHeaderMenu(
                        onOpenKeyboardShortcuts: {
                            showMenu = false
                            onOpenKeyboardShortcuts?()
                        },
                        onOpenSettings: {
                            showMenu = false
                            onOpenSettings?()
                        }
                    )
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, LayoutMetrics.sidebarInset)
        .frame(height: LayoutMetrics.toolbarHeight)
        .background(colors.toolbarBackground)
    }
}

// MARK: - Sidebar Header Menu

struct SidebarHeaderMenu: View {
    @Environment(\.colorScheme) private var colorScheme

    var onOpenKeyboardShortcuts: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onOpenKeyboardShortcuts {
                Button(action: onOpenKeyboardShortcuts) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "keyboard")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.md)

                        Text("Keyboard Shortcuts")
                            .font(Typography.bodySmall)
                            .foregroundStyle(colors.foreground)

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }

            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "gearshape")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.md)

                        Text("Settings")
                            .font(Typography.bodySmall)
                            .foregroundStyle(colors.foreground)

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(minWidth: 180)
        .background(colors.card)
    }
}

// MARK: - Keyboard Shortcuts Dialog

struct KeyboardShortcutsDialog: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.mutedForeground)
                }
                .buttonGhost(size: .icon)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            ShadcnDivider()

            // Shortcuts list
            VStack(alignment: .leading, spacing: Spacing.sm) {
                KeyboardShortcutRow(
                    title: "Open Command Menu",
                    shortcut: "⌘K"
                )
                KeyboardShortcutRow(
                    title: "Toggle Zen Mode",
                    shortcut: "⌘K Z"
                )
            }
            .padding(Spacing.lg)
        }
        .frame(width: 320)
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .shadow(color: Color(hex: "0D0D0D").opacity(0.2), radius: 16, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }
}

// MARK: - Keyboard Shortcut Row

struct KeyboardShortcutRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let shortcut: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(colors.foreground)

            Spacer()

            Text(shortcut)
                .font(Typography.mono)
                .foregroundStyle(colors.mutedForeground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Keyboard Shortcuts Dialog Overlay

struct KeyboardShortcutsOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Backdrop
            Color(hex: "0D0D0D").opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Dialog centered
            KeyboardShortcutsDialog(isPresented: $isPresented)
        }
        .transition(.opacity)
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
                        .font(Typography.sidebarProject)
                        .foregroundStyle(colors.foreground.opacity(0.9))

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
                    .font(Typography.sidebarItem)
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
                    .font(Typography.sidebarItem)
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
                    .font(Typography.sidebarItem)
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
                    .font(Typography.sidebarItem)
                    .foregroundStyle(colors.sidebarText)
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
