//
//  AppearanceSettings.swift
//  rocketry-macos
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
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                // Header
                Text("Appearance")
                    .font(Typography.h2)
                    .foregroundStyle(colors.foreground)

                Text("Customize how the app looks on your device.")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)

                ShadcnDivider()

                // Theme selection
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Theme")
                        .font(Typography.h4)
                        .foregroundStyle(colors.foreground)

                    Text("Select your preferred color scheme")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)

                    // Theme cards
                    HStack(spacing: Spacing.lg) {
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

                Spacer()
            }
            .padding(Spacing.xxl)
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

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Spacing.md) {
                // Preview
                ThemePreview(mode: mode)
                    .frame(width: 120, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .stroke(isSelected ? colors.primary : colors.border, lineWidth: isSelected ? BorderWidth.thick : BorderWidth.default)
                    )

                // Label
                HStack(spacing: Spacing.sm) {
                    Image(systemName: mode.iconName)
                        .font(.system(size: IconSize.sm))

                    Text(mode.rawValue)
                        .font(Typography.bodySmall)
                }
                .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: IconSize.lg))
                        .foregroundStyle(colors.primary)
                } else {
                    Circle()
                        .stroke(colors.border, lineWidth: BorderWidth.default)
                        .frame(width: IconSize.lg, height: IconSize.lg)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .fill(isSelected ? colors.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Preview

struct ThemePreview: View {
    let mode: ThemeMode

    private var backgroundColor: Color {
        switch mode {
        case .system:
            return Color(hex: "18181b") // Zinc 900
        case .light:
            return Color.white
        case .dark:
            return Color(hex: "09090b") // Zinc 950
        }
    }

    private var sidebarColor: Color {
        switch mode {
        case .system:
            return Color(hex: "27272a") // Zinc 800
        case .light:
            return Color(hex: "f4f4f5") // Zinc 100
        case .dark:
            return Color(hex: "18181b") // Zinc 900
        }
    }

    private var textColor: Color {
        switch mode {
        case .system:
            return Color(hex: "fafafa") // Zinc 50
        case .light:
            return Color(hex: "09090b") // Zinc 950
        case .dark:
            return Color(hex: "fafafa") // Zinc 50
        }
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
