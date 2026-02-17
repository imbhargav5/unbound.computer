//
//  SettingsPageContainer.swift
//  unbound-macos
//
//  Reusable container for settings pages with consistent header and layout
//

import SwiftUI

struct SettingsPageContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxxl) {
                // Page header
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(title)
                        .font(Typography.pageTitle)
                        .tracking(-0.5)
                        .foregroundStyle(colors.foreground)

                    Text(subtitle)
                        .font(GeistFont.sans(size: FontSize.lg, weight: .regular))
                        .foregroundStyle(colors.sidebarMeta)
                }

                ShadcnDivider()

                content()
            }
            .padding(.vertical, Spacing.xxxxxl)
            .padding(.horizontal, 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.background)
    }
}
