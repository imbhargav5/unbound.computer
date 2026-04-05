//
//  MarkdownProseTokens.swift
//  unbound-macos
//
//  Prose + inline code tokens mapped from Pencil nodes:
//  - Rich text prose: y3oe1
//  - Inline code chip: Nt3sY
//

import SwiftUI

enum MarkdownProseTokens {
    // MARK: - Typography

    static let paragraphFontSize: CGFloat = 13
    static let paragraphLineSpacing: CGFloat = 4

    static let headingH1FontSize: CGFloat = 22
    static let headingH2FontSize: CGFloat = 17
    static let headingH3FontSize: CGFloat = 14
    static let headingLineSpacing: CGFloat = 3

    @MainActor
    static var paragraphFont: Font {
        GeistFont.sans(size: paragraphFontSize, weight: .regular)
    }

    @MainActor
    static var headingH1Font: Font {
        GeistFont.sans(size: headingH1FontSize, weight: .bold)
    }

    @MainActor
    static var headingH2Font: Font {
        GeistFont.sans(size: headingH2FontSize, weight: .semibold)
    }

    @MainActor
    static var headingH3Font: Font {
        GeistFont.sans(size: headingH3FontSize, weight: .semibold)
    }

    // MARK: - Inline Code Chip (Nt3sY)

    static let inlineCodeFontSize: CGFloat = 12
    static let inlineCodeCornerRadius: CGFloat = 4
    static let inlineCodePaddingVertical: CGFloat = 2
    static let inlineCodePaddingHorizontal: CGFloat = 6

    @MainActor
    static var inlineCodeFont: Font {
        GeistFont.mono(size: inlineCodeFontSize, weight: .regular)
    }

    // MARK: - Blockquote + Rule

    static let blockquoteRailWidth: CGFloat = 3
    static let blockquoteVerticalPadding: CGFloat = 10
    static let blockquoteHorizontalPadding: CGFloat = 16
    static let horizontalRuleHeight: CGFloat = 1

    // MARK: - Colors

    static func headingH1Color(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "F5F5F5") : colors.foreground
    }

    static func headingH2Color(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "E5E5E5") : colors.textSecondary
    }

    static func headingH3Color(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "D4D4D4") : colors.textSecondary
    }

    static func paragraphColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "B3B3B3") : colors.textMuted
    }

    static func boldColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "E5E5E5") : colors.foreground
    }

    static func italicColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        paragraphColor(colors: colors, colorScheme: colorScheme)
    }

    static func linkColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "6BA3E8") : colors.info
    }

    static func strikethroughColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "6B6B6B") : colors.textInactive
    }

    static func inlineCodeTextColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "E09F5E") : colors.primaryAction
    }

    static func inlineCodeBackground(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "1E1E1E") : colors.secondary
    }

    static func blockquoteTextColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "9A9A9A") : colors.mutedForeground
    }

    static func blockquoteRailColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "3A3A3A") : colors.border
    }

    static func horizontalRuleColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "2A2A2A") : colors.border
    }
}
