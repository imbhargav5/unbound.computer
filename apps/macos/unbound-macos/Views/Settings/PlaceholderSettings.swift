//
//  PlaceholderSettings.swift
//  unbound-macos
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
        SettingsPageContainer(title: section.rawValue, subtitle: "This feature is coming soon.") {
            VStack(spacing: Spacing.lg) {
                Image(systemName: section.iconName)
                    .font(.system(size: Spacing.xxxxxl))
                    .foregroundStyle(colors.mutedForeground)

                Text("Settings for \(section.rawValue.lowercased()) will appear here.")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)

                Badge("Coming Soon", variant: .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.xxxxl)
        }
    }
}

#if DEBUG

#Preview {
    PlaceholderSettings(section: .general)
        .frame(width: 400, height: 300)
}

#endif
