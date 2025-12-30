//
//  EmptyStateViews.swift
//  unbound-macos
//
//  Empty state components for when no content is available
//

import SwiftUI

// MARK: - Projects Empty State (Sidebar)

struct ProjectsEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var onAddRepository: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl)
                    .fill(colors.muted.opacity(0.5))
                    .frame(width: 64, height: 64)

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(colors.mutedForeground)
            }

            // Text
            VStack(spacing: Spacing.sm) {
                Text("No projects yet")
                    .font(Typography.bodySmall)
                    .fontWeight(.medium)
                    .foregroundStyle(colors.foreground)

                Text("Add a repository to get started")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            // CTA Button
            Button(action: onAddRepository) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: IconSize.sm, weight: .medium))
                    Text("Add Repository")
                        .font(Typography.bodySmall)
                        .fontWeight(.medium)
                }
                .foregroundStyle(colors.primaryForeground)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Workspace Empty State (Main Content)

struct WorkspaceEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var hasProjects: Bool
    var onAddRepository: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // Illustration
            ZStack {
                // Background circles for visual interest
                Circle()
                    .fill(colors.muted.opacity(0.3))
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(colors.muted.opacity(0.5))
                    .frame(width: 120, height: 120)

                // Main icon
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(colors.mutedForeground)

                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(colors.info.opacity(0.8))
                        .offset(x: 24, y: -32)
                }
            }

            // Content
            VStack(spacing: Spacing.md) {
                Text(hasProjects ? "Select a Workspace" : "Welcome to Unbound")
                    .font(Typography.h3)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.foreground)

                Text(hasProjects
                     ? "Choose a workspace from the sidebar to start coding with Claude"
                     : "Your AI-powered development environment")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if !hasProjects {
                // Getting started section
                VStack(spacing: Spacing.lg) {
                    Text("Get started")
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.mutedForeground)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Button(action: onAddRepository) {
                        HStack(spacing: Spacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(colors.info.opacity(0.1))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: IconSize.lg))
                                    .foregroundStyle(colors.info)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add your first repository")
                                    .font(Typography.bodySmall)
                                    .fontWeight(.medium)
                                    .foregroundStyle(colors.foreground)

                                Text("Import an existing project to get started")
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.mutedForeground)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: IconSize.sm, weight: .medium))
                                .foregroundStyle(colors.mutedForeground)
                        }
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .fill(colors.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.lg)
                                        .stroke(colors.border, lineWidth: BorderWidth.default)
                                )
                        )
                        .frame(maxWidth: 360)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, Spacing.lg)
            }

            Spacer()

            // Keyboard shortcut hint
            if hasProjects {
                HStack(spacing: Spacing.sm) {
                    KeyboardShortcutHint(keys: ["Cmd", "1-9"])
                    Text("to quickly switch workspaces")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }
                .padding(.bottom, Spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keyboard Shortcut Hint

struct KeyboardShortcutHint: View {
    @Environment(\.colorScheme) private var colorScheme

    let keys: [String]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(Typography.micro)
                    .fontWeight(.medium)
                    .foregroundStyle(colors.mutedForeground)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(colors.muted)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
        }
    }
}

// MARK: - Previews

#Preview("Sidebar Empty State") {
    ProjectsEmptyState(onAddRepository: {})
        .frame(width: 280, height: 500)
        .background(ShadcnColors.Dark.background)
}

#Preview("Workspace Empty - No Projects") {
    WorkspaceEmptyState(hasProjects: false, onAddRepository: {})
        .frame(width: 800, height: 600)
        .background(ShadcnColors.Dark.background)
}

#Preview("Workspace Empty - Has Projects") {
    WorkspaceEmptyState(hasProjects: true, onAddRepository: {})
        .frame(width: 800, height: 600)
        .background(ShadcnColors.Dark.background)
}
