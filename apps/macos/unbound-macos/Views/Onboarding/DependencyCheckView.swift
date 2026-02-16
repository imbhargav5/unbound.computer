//
//  DependencyCheckView.swift
//  unbound-macos
//
//  Gate view shown after authentication to verify required system
//  dependencies (Claude Code CLI) are installed before entering
//  the workspace. GitHub CLI is optional — a non-blocking warning
//  is shown if missing.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct DependencyCheckView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Group {
            switch appState.dependencyStatus {
            case .unchecked, .checking:
                checkingView
            case .claudeMissing:
                claudeMissingView
            case .satisfied:
                // Should not remain visible — ContentView routes away
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
        .task {
            if appState.dependencyStatus == .unchecked {
                await appState.checkDependencies()
            }
        }
    }

    // MARK: - Checking State

    private var checkingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            VStack(spacing: Spacing.sm) {
                Text("Checking System Requirements")
                    .font(Typography.title2)
                    .foregroundColor(colors.foreground)

                Text("Verifying required tools are installed...")
                    .font(Typography.body)
                    .foregroundColor(colors.mutedForeground)
            }
        }
    }

    // MARK: - Claude Missing State

    private var claudeMissingView: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            VStack(spacing: Spacing.sm) {
                Text("Claude Code Required")
                    .font(Typography.title2)
                    .foregroundColor(colors.foreground)

                Text("Unbound requires the Claude Code CLI to function.\nPlease install it and try again.")
                    .font(Typography.body)
                    .foregroundColor(colors.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            // Install instructions
            VStack(spacing: Spacing.sm) {
                Text("Install via npm:")
                    .font(Typography.bodySmall)
                    .foregroundColor(colors.mutedForeground)

                Text("npm install -g @anthropic-ai/claude-code")
                    .font(Typography.code)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(colors.muted.opacity(0.5))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }

            VStack(spacing: Spacing.md) {
                Button {
                    Task {
                        await appState.recheckDependencies()
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text("Check Again")
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                }
                .buttonStyle(.borderedProminent)

                Link("Claude Code Documentation", destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code")!)
                    .font(Typography.caption)
                    .foregroundColor(colors.primary)
            }
        }
    }
}

// MARK: - GitHub CLI Warning Banner

/// Dismissible banner shown in the workspace when GitHub CLI is not installed.
struct GhMissingBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("ghWarningDismissed") private var isDismissed = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        if !isDismissed {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                Text("GitHub CLI (gh) is not installed. Some features may be limited.")
                    .font(Typography.caption)
                    .foregroundColor(colors.foreground)

                Spacer()

                Link("Install", destination: URL(string: "https://cli.github.com")!)
                    .font(Typography.caption)
                    .foregroundColor(colors.primary)

                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(colors.mutedForeground)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(colors.muted.opacity(0.3))
        }
    }
}

// MARK: - Previews

#Preview("Checking") {
    let state = AppState()
    state.configureForPreview(dependencyStatus: .checking)
    return DependencyCheckView()
        .environment(state)
        .frame(width: 600, height: 500)
}

#Preview("Claude Missing") {
    let state = AppState()
    state.configureForPreview(dependencyStatus: .claudeMissing)
    return DependencyCheckView()
        .environment(state)
        .frame(width: 600, height: 500)
}

#Preview("GH Warning Banner") {
    GhMissingBanner()
        .frame(width: 600)
}
