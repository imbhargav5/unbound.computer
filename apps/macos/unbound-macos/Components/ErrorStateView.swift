//
//  ErrorStateView.swift
//  unbound-macos
//
//  Reusable error state component with consistent styling and animations
//

import SwiftUI

struct ErrorStateView: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: String
    var message: String?
    var detail: String?
    var iconColor: Color?

    @State private var hasAppeared = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var resolvedIconColor: Color {
        iconColor ?? colors.destructive
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Icon in rounded container
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl)
                    .fill(resolvedIconColor.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(resolvedIconColor)
            }
            .scaleFade(isVisible: hasAppeared, initialScale: 0.8)

            // Title and message
            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.h4)
                    .fontWeight(.medium)
                    .foregroundStyle(colors.foreground)
                    .slideIn(isVisible: hasAppeared, from: .bottom, delay: 0.1)

                if let message {
                    Text(message)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)
                        .multilineTextAlignment(.center)
                        .slideIn(isVisible: hasAppeared, from: .bottom, delay: 0.15)
                }
            }

            // Detail box (optional)
            if let detail {
                Text(detail)
                    .font(Typography.code)
                    .foregroundStyle(colors.mutedForeground)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .frame(maxWidth: 360)
                    .background(colors.muted.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .slideIn(isVisible: hasAppeared, from: .bottom, delay: 0.2)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Error - Failed to load file") {
    ErrorStateView(
        icon: "doc.text",
        title: "Failed to load file",
        message: "The file could not be found or read"
    )
    .frame(width: 600, height: 400)
    .background(ShadcnColors.Dark.background)
}

#Preview("Error - Failed to load diff") {
    ErrorStateView(
        icon: "arrow.left.arrow.right",
        title: "Failed to load diff",
        message: "Could not generate diff for this file"
    )
    .frame(width: 600, height: 400)
    .background(ShadcnColors.Dark.background)
}

#Preview("Error - Workspace not found") {
    ErrorStateView(
        icon: "folder.badge.questionmark",
        title: "Workspace not found",
        message: "The workspace directory no longer exists:",
        detail: "/Users/example/Projects/my-project"
    )
    .frame(width: 600, height: 400)
    .background(ShadcnColors.Dark.background)
}

#Preview("Info - No diff available") {
    ErrorStateView(
        icon: "doc.text.magnifyingglass",
        title: "No diff available",
        message: "There are no changes to display for this file",
        iconColor: ShadcnColors.Dark.mutedForeground
    )
    .frame(width: 600, height: 400)
    .background(ShadcnColors.Dark.background)
}

#endif
