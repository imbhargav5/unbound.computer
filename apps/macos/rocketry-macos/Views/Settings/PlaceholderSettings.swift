//
//  PlaceholderSettings.swift
//  rocketry-macos
//
//  Shadcn-styled placeholder settings
//

import SwiftUI

struct PlaceholderSettings: View {
    @Environment(\.colorScheme) private var colorScheme

    let section: SettingsSection

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Icon
            Image(systemName: section.iconName)
                .font(.system(size: Spacing.xxxxxl))
                .foregroundStyle(colors.mutedForeground)

            // Title
            Text(section.rawValue)
                .font(Typography.h2)
                .foregroundStyle(colors.foreground)

            // Description
            Text("Settings for \(section.rawValue.lowercased()) will appear here.")
                .font(Typography.body)
                .foregroundStyle(colors.mutedForeground)
                .multilineTextAlignment(.center)

            // Coming soon badge
            Badge("Coming Soon", variant: .secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }
}

#Preview {
    PlaceholderSettings(section: .general)
        .frame(width: 400, height: 300)
}
