//
//  AppearanceSettings.swift
//  unbound-macos
//
//  Shadcn-styled appearance settings
//

import SwiftUI

struct AppearanceSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        @Bindable var state = appState

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                Text("Appearance")
                    .font(Typography.h2)
                    .foregroundStyle(colors.foreground)

                Text("Customize how the app looks on your device.")
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.mutedForeground)

                ShadcnDivider()

                // Theme selection
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Theme")
                        .font(Typography.h4)
                        .foregroundStyle(colors.foreground)

                    Text("Select your preferred color scheme")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)

                    // Theme cards
                    HStack(spacing: Spacing.md) {
                        ForEach(ThemeMode.allCases) { mode in
                            ThemeCard(
                                mode: mode,
                                isSelected: appState.themeMode == mode,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: Duration.default)) {
                                        state.themeMode = mode
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.background)
    }
}

// MARK: - Theme Card

struct ThemeCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let mode: ThemeMode
    let isSelected: Bool
    var onSelect: () -> Void

    private var isAvailable: Bool {
        mode == .dark
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: {
            if isAvailable {
                onSelect()
            }
        }) {
            VStack(spacing: Spacing.sm) {
                // Preview
                ThemePreview(mode: mode)
                    .frame(width: 100, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(isSelected ? colors.primary : colors.border, lineWidth: isSelected ? BorderWidth.thick : BorderWidth.default)
                    )
                    .opacity(isAvailable ? 1 : 0.5)

                // Label
                HStack(spacing: Spacing.xs) {
                    Image(systemName: mode.iconName)
                        .font(.system(size: IconSize.xs))

                    Text(mode.rawValue)
                        .font(Typography.caption)
                }
                .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)
                .opacity(isAvailable ? 1 : 0.5)

                // Coming soon / Selection indicator
                if !isAvailable {
                    Text("Coming soon")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: IconSize.md))
                        .foregroundStyle(colors.primary)
                } else {
                    Circle()
                        .stroke(colors.border, lineWidth: BorderWidth.default)
                        .frame(width: IconSize.md, height: IconSize.md)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(isSelected ? colors.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }
}

// MARK: - Theme Preview

struct ThemePreview: View {
    let mode: ThemeMode

    private var previewColors: ThemeColors {
        ThemeColors(mode == .light ? .light : .dark)
    }

    private var backgroundColor: Color {
        previewColors.background
    }

    private var sidebarColor: Color {
        previewColors.card
    }

    private var textColor: Color {
        previewColors.foreground
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar preview
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(textColor.opacity(0.3))
                    .frame(width: 24, height: 4)

                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(textColor.opacity(0.2))
                    .frame(width: 20, height: 3)

                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(textColor.opacity(0.2))
                    .frame(width: 22, height: 3)

                Spacer()
            }
            .padding(Spacing.sm)
            .frame(width: 36)
            .background(sidebarColor)

            // Main content preview
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(textColor.opacity(0.2))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(textColor.opacity(0.15))
                    .frame(width: 50, height: 4)

                Spacer()

                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(textColor.opacity(0.1))
                    .frame(height: 16)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
        }
    }
}

#Preview {
    AppearanceSettings()
        .environment(AppState())
        .frame(width: 500, height: 400)
}
