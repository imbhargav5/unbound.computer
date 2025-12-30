//
//  DesignTokens.swift
//  rocketry-macos
//
//  Shadcn-inspired design tokens for consistent UI
//

import SwiftUI

// MARK: - Spacing (4px base grid)

enum Spacing {
    /// 4pt - Extra small spacing
    static let xs: CGFloat = 4
    /// 8pt - Small spacing
    static let sm: CGFloat = 8
    /// 12pt - Medium spacing
    static let md: CGFloat = 12
    /// 16pt - Large spacing
    static let lg: CGFloat = 16
    /// 20pt - Extra large spacing
    static let xl: CGFloat = 20
    /// 24pt - 2x large spacing
    static let xxl: CGFloat = 24
    /// 32pt - 3x large spacing
    static let xxxl: CGFloat = 32
    /// 40pt - 4x large spacing
    static let xxxxl: CGFloat = 40
    /// 48pt - 5x large spacing
    static let xxxxxl: CGFloat = 48
}

// MARK: - Border Radius

enum Radius {
    /// 2pt - Extra small radius
    static let xs: CGFloat = 2
    /// 4pt - Small radius
    static let sm: CGFloat = 4
    /// 6pt - Medium radius (default)
    static let md: CGFloat = 6
    /// 8pt - Large radius
    static let lg: CGFloat = 8
    /// 12pt - Extra large radius
    static let xl: CGFloat = 12
    /// 16pt - 2x large radius
    static let xxl: CGFloat = 16
    /// Full pill radius
    static let full: CGFloat = 9999
}

// MARK: - Font Sizes

enum FontSize {
    /// 10pt - Extra extra small
    static let xxs: CGFloat = 10
    /// 11pt - Extra small
    static let xs: CGFloat = 11
    /// 12pt - Small
    static let sm: CGFloat = 12
    /// 13pt - Small-medium
    static let smMd: CGFloat = 13
    /// 14pt - Base/default
    static let base: CGFloat = 14
    /// 16pt - Large
    static let lg: CGFloat = 16
    /// 18pt - Extra large
    static let xl: CGFloat = 18
    /// 20pt - 2x large
    static let xxl: CGFloat = 20
    /// 24pt - 3x large
    static let xxxl: CGFloat = 24
    /// 30pt - Display small
    static let display: CGFloat = 30
}

// MARK: - Icon Sizes

enum IconSize {
    /// 10pt - Extra small icons
    static let xs: CGFloat = 10
    /// 12pt - Small icons
    static let sm: CGFloat = 12
    /// 14pt - Medium icons (default)
    static let md: CGFloat = 14
    /// 16pt - Large icons
    static let lg: CGFloat = 16
    /// 20pt - Extra large icons
    static let xl: CGFloat = 20
    /// 24pt - 2x large icons
    static let xxl: CGFloat = 24
}

// MARK: - Border Width

enum BorderWidth {
    /// 0.5pt - Hairline
    static let hairline: CGFloat = 0.5
    /// 1pt - Default border
    static let `default`: CGFloat = 1
    /// 2pt - Thick border
    static let thick: CGFloat = 2
}

// MARK: - Animation Durations

enum Duration {
    /// 0.1s - Fast animation
    static let fast: Double = 0.1
    /// 0.15s - Default animation
    static let `default`: Double = 0.15
    /// 0.2s - Medium animation
    static let medium: Double = 0.2
    /// 0.3s - Slow animation
    static let slow: Double = 0.3
}
