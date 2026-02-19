//
//  ChatConversationTokens.swift
//  unbound-macos
//
//  Scoped layout/typography tokens for conversation message rendering.
//  These tokens intentionally do not apply to headers, composer, footer, or tool surfaces.
//

import SwiftUI

enum ChatConversationContentStyle {
    case `default`
    case conversationProse

    var isConversationProse: Bool {
        self == .conversationProse
    }
}

enum ChatConversationTokens {
    // MARK: - Message Row Layout

    static let rowHorizontalPadding: CGFloat = Spacing.lg
    static let rowVerticalPadding: CGFloat = Spacing.xs
    static let userRowVerticalMargin: CGFloat = Spacing.md
    static let rowContentSpacing: CGFloat = Spacing.sm
    static let sideSpacerMinWidth: CGFloat = 60

    // MARK: - User Bubble

    static let userBubbleHorizontalPadding: CGFloat = Spacing.md
    static let userBubbleVerticalPadding: CGFloat = Spacing.sm
    static let userBubbleCornerRadius: CGFloat = Spacing.lg

    // MARK: - Prose Rhythm

    static let proseBlockSpacing: CGFloat = Spacing.sm
    static let proseAreaVerticalMargin: CGFloat = Spacing.md
    static let proseLineSpacing: CGFloat = Spacing.xs
    static let proseListItemSpacing: CGFloat = Spacing.xs
    static let proseListMarkerSpacing: CGFloat = Spacing.sm
    static let proseListIndentStep: CGFloat = Spacing.md
    static let proseHeadingTopLarge: CGFloat = Spacing.lg
    static let proseHeadingTopStandard: CGFloat = Spacing.md
    static let proseHeadingBottom: CGFloat = Spacing.xs
    static let proseDividerVerticalPadding: CGFloat = Spacing.sm
    static let proseCodeBlockVerticalPadding: CGFloat = Spacing.xs
    static let proseBlockquoteVerticalPadding: CGFloat = Spacing.xs

    // MARK: - Table Rhythm

    static let tableOuterVerticalPadding: CGFloat = Spacing.xs
    static let tableCellHorizontalPadding: CGFloat = Spacing.md
    static let tableCellVerticalPadding: CGFloat = Spacing.xs
    static let tableCellLineSpacing: CGFloat = Spacing.xs
}
