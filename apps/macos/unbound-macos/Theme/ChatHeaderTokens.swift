//
//  ChatHeaderTokens.swift
//  unbound-macos
//
//  Specs mapped from Pencil nodes d391K + FAEi4 (Session View chat header tabs)
//

import SwiftUI

enum ChatHeaderTokens {
    // Header container
    static let headerHeight: CGFloat = LayoutMetrics.compactToolbarHeight // 36
    static let bottomBorderWidth: CGFloat = BorderWidth.default // 1

    // Tab layout
    static let tabContentSpacing: CGFloat = Spacing.sm // 8
    static let tabHorizontalPadding: CGFloat = Spacing.md // 12
    static let tabSeparatorWidth: CGFloat = BorderWidth.default // 1

    // Tab label typography (Geist 12 regular)
    static let tabFontSize: CGFloat = FontSize.sm // 12
    static let tabFontWeight: Font.Weight = .regular

    // Diff badge typography + geometry
    static let badgeFontSize: CGFloat = 9
    static let badgeFontWeight: Font.Weight = .medium
    static let badgeHorizontalPadding: CGFloat = 6
    static let badgeVerticalPadding: CGFloat = 1
    static let badgeCornerRadius: CGFloat = Radius.lg // 4

    // Close icon geometry
    static let closeIconSize: CGFloat = IconSize.sm // 12
    static let closeIconFrameSize: CGFloat = IconSize.sm // 12
}
