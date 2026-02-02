//
//  GeneralSettings.swift
//  unbound-macos
//
//  General settings including text size preferences
//

import SwiftUI

struct GeneralSettings: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var localSettings: LocalSettings {
        LocalSettings.shared
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                Text("General")
                    .font(Typography.h2)
                    .foregroundStyle(colors.foreground)

                Text("Configure general app preferences.")
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.mutedForeground)

                ShadcnDivider()

                // Text Size section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Text Size")
                        .font(Typography.h4)
                        .foregroundStyle(colors.foreground)

                    Text("Adjust the interface text size")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)

                    // Font size cards
                    HStack(spacing: Spacing.md) {
                        ForEach(FontSizePreset.allCases) { preset in
                            FontSizeCard(
                                preset: preset,
                                isSelected: localSettings.fontSizePreset == preset,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: Duration.default)) {
                                        localSettings.fontSizePreset = preset
                                    }
                                }
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.background)
    }
}

// MARK: - Font Size Card

struct FontSizeCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let preset: FontSizePreset
    let isSelected: Bool
    var onSelect: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Spacing.sm) {
                // Preview
                FontSizePreview(preset: preset)
                    .frame(width: 100, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(isSelected ? colors.primary : colors.border, lineWidth: isSelected ? BorderWidth.thick : BorderWidth.default)
                    )

                // Label
                HStack(spacing: Spacing.xs) {
                    Image(systemName: preset.iconName)
                        .font(.system(size: IconSize.xs))

                    Text(preset.rawValue)
                        .font(Typography.caption)
                }
                .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)

                // Selection indicator
                if isSelected {
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
    }
}

// MARK: - Font Size Preview

struct FontSizePreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let preset: FontSizePreset

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var scale: CGFloat {
        preset.scaleFactor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Title line
            RoundedRectangle(cornerRadius: Radius.xs)
                .fill(colors.foreground.opacity(0.3))
                .frame(width: 40 * scale, height: 5 * scale)

            // Body lines
            RoundedRectangle(cornerRadius: Radius.xs)
                .fill(colors.foreground.opacity(0.2))
                .frame(width: 60 * scale, height: 3 * scale)

            RoundedRectangle(cornerRadius: Radius.xs)
                .fill(colors.foreground.opacity(0.2))
                .frame(width: 50 * scale, height: 3 * scale)

            RoundedRectangle(cornerRadius: Radius.xs)
                .fill(colors.foreground.opacity(0.15))
                .frame(width: 55 * scale, height: 3 * scale)

            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.muted)
    }
}

#Preview {
    GeneralSettings()
        .frame(width: 500, height: 400)
}
