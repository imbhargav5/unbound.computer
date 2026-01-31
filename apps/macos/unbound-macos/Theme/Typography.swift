//
//  Typography.swift
//  unbound-macos
//
//  SF Mono typography system for dev-tool aesthetic
//

import SwiftUI

// MARK: - Typography

enum Typography {
    // MARK: - Display

    /// 30pt Light Mono - Large feature headlines (onboarding)
    static let displayLight = Font.system(size: FontSize.display, weight: .light, design: .monospaced)

    /// 28pt Light Mono - Feature headlines
    static let headline = Font.system(size: 28, weight: .light, design: .monospaced)

    // MARK: - Headings

    /// 24pt Bold Mono - Page titles
    static let h1 = Font.system(size: FontSize.xxxl, weight: .bold, design: .monospaced)

    /// 24pt Semibold Mono - Large titles (replaces .title)
    static let title = Font.system(size: FontSize.xxxl, weight: .semibold, design: .monospaced)

    /// 20pt Semibold Mono - Section headers
    static let h2 = Font.system(size: FontSize.xxl, weight: .semibold, design: .monospaced)

    /// 20pt Bold Mono - Subsection titles (replaces .title2)
    static let title2 = Font.system(size: FontSize.xxl, weight: .bold, design: .monospaced)

    /// 18pt Semibold Mono - Subsection headers
    static let h3 = Font.system(size: FontSize.xl, weight: .semibold, design: .monospaced)

    /// 18pt Bold Mono - Small titles (replaces .title3)
    static let title3 = Font.system(size: FontSize.xl, weight: .bold, design: .monospaced)

    /// 16pt Medium Mono - Card titles
    static let h4 = Font.system(size: FontSize.lg, weight: .medium, design: .monospaced)

    // MARK: - Body Text

    /// 14pt Regular Mono - Default body text
    static let body = Font.system(size: FontSize.base, weight: .regular, design: .monospaced)

    /// 14pt Medium Mono - Emphasized body text
    static let bodyMedium = Font.system(size: FontSize.base, weight: .medium, design: .monospaced)

    /// 13pt Regular Mono - Smaller body text
    static let bodySmall = Font.system(size: FontSize.smMd, weight: .regular, design: .monospaced)

    // MARK: - UI Elements

    /// 12pt Medium Mono - Labels, buttons
    static let label = Font.system(size: FontSize.sm, weight: .medium, design: .monospaced)

    /// 12pt Regular Mono - Secondary labels
    static let labelRegular = Font.system(size: FontSize.sm, weight: .regular, design: .monospaced)

    /// 11pt Regular Mono - Captions, hints
    static let caption = Font.system(size: FontSize.xs, weight: .regular, design: .monospaced)

    /// 11pt Medium Mono - Badges, tags
    static let captionMedium = Font.system(size: FontSize.xs, weight: .medium, design: .monospaced)

    /// 10pt Regular Mono - Extra small text
    static let micro = Font.system(size: FontSize.xxs, weight: .regular, design: .monospaced)

    // MARK: - Code/Terminal

    /// 13pt Regular Mono - Code blocks
    static let code = Font.system(size: FontSize.smMd, weight: .regular, design: .monospaced)

    /// 12pt Regular Mono - Terminal text
    static let terminal = Font.system(size: FontSize.sm, weight: .regular, design: .monospaced)

    /// 11pt Regular Mono - Monospace for hashes, IDs
    static let mono = Font.system(size: FontSize.xs, weight: .regular, design: .monospaced)

    // MARK: - Special

    /// 14pt Semibold Mono - Navigation items
    static let nav = Font.system(size: FontSize.base, weight: .semibold, design: .monospaced)

    /// 12pt Semibold Mono - Tab labels
    static let tab = Font.system(size: FontSize.sm, weight: .semibold, design: .monospaced)
}

// MARK: - Text Style View Modifier

struct TypographyModifier: ViewModifier {
    let font: Font
    let color: Color?

    init(font: Font, color: Color? = nil) {
        self.font = font
        self.color = color
    }

    func body(content: Content) -> some View {
        if let color = color {
            content
                .font(font)
                .foregroundStyle(color)
        } else {
            content
                .font(font)
        }
    }
}

// MARK: - View Extensions

extension View {
    func typography(_ font: Font, color: Color? = nil) -> some View {
        modifier(TypographyModifier(font: font, color: color))
    }

    // Convenience methods
    func h1() -> some View { typography(Typography.h1) }
    func h2() -> some View { typography(Typography.h2) }
    func h3() -> some View { typography(Typography.h3) }
    func h4() -> some View { typography(Typography.h4) }
    func bodyText() -> some View { typography(Typography.body) }
    func bodySmallText() -> some View { typography(Typography.bodySmall) }
    func labelText() -> some View { typography(Typography.label) }
    func captionText() -> some View { typography(Typography.caption) }
    func codeText() -> some View { typography(Typography.code) }
    func terminalText() -> some View { typography(Typography.terminal) }
}
