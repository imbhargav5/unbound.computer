//
//  TerminalFooterTabTokens.swift
//  unbound-macos
//
//  Specs mapped from Pencil node iP7zR (Session View - Terminal Open)
//  Components referenced: "Bottom Tabs" (TFzLm) + "terminalTab" (vmcoc)
//

import SwiftUI

enum TerminalFooterTabTokens {
    // Layout
    static let barHeight: CGFloat = Spacing.xxxxxl // 48
    static let barPaddingX: CGFloat = Spacing.lg // 16
    static let tabPaddingX: CGFloat = Spacing.xxl // 24
    static let tabCornerRadius: CGFloat = Radius.xxl // 8 (top corners in Pencil)
    static let tabBorderWidth: CGFloat = BorderWidth.`default`
    static let closeButtonSize: CGFloat = 28
    static let closeButtonCornerRadius: CGFloat = Radius.xl // 6
    static let closeIconSize: CGFloat = 11
    static let tabContentSpacing: CGFloat = Spacing.sm // 8
    static let addButtonSize: CGFloat = 28
    static let addIconSize: CGFloat = 12
    static let controlPaddingX: CGFloat = Spacing.sm // 8

    // Typography
    static let tabFontSize: CGFloat = FontSize.base // 14
    static let tabFontWeight: Font.Weight = .semibold
    static let tabLetterSpacing: CGFloat = 0.2

    // Color mapping notes (use ThemeColors in views)
    // - Bar background: #111111 -> colors.muted
    // - Bar divider: #252525 -> colors.borderSecondary
    // - Selected tab background: #1A1A1A -> colors.secondary
    // - Tab right divider: #1F1F1F -> colors.border
}
