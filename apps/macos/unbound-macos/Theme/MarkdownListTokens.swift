//
//  MarkdownListTokens.swift
//  unbound-macos
//
//  Session markdown list tokens mapped from Pencil nodes:
//  - Unordered list: Tjnze (inner: kluKI)
//  - Ordered list: 5EFvs (inner: 7Rn84)
//

import SwiftUI

enum MarkdownListTokens {
    // MARK: - Container layout

    static let listPaddingTop: CGFloat = 4
    static let listPaddingRight: CGFloat = 0
    static let listPaddingBottom: CGFloat = 4
    static let listPaddingLeft: CGFloat = 16

    static let itemVerticalSpacing: CGFloat = 4
    static let markerToTextSpacing: CGFloat = 8
    static let indentStep: CGFloat = 16

    // Ordered list marker column width from Pencil snapshot (`rtIVp` width)
    static let orderedMarkerColumnWidth: CGFloat = 16

    // MARK: - Typography

    static let markerFontSize: CGFloat = 13
    static let itemTextFontSize: CGFloat = 13
    static let headingFontSize: CGFloat = 14
    static let headingLineSpacing: CGFloat = 4
    static let headingBottomSpacing: CGFloat = 8

    @MainActor
    static var unorderedMarkerFont: Font {
        GeistFont.sans(size: markerFontSize, weight: .regular)
    }

    @MainActor
    static var orderedMarkerFont: Font {
        GeistFont.mono(size: markerFontSize, weight: .regular)
    }

    @MainActor
    static var itemTextFont: Font {
        GeistFont.sans(size: itemTextFontSize, weight: .regular)
    }

    @MainActor
    static var headingFont: Font {
        GeistFont.sans(size: headingFontSize, weight: .semibold)
    }

    static func headingColor(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "E5E5E5") : colors.textSecondary
    }
}
