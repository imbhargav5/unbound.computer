//
//  Typography.swift
//  mockup-macos
//
//  Geist typography system for modern dev-tool aesthetic
//

import SwiftUI
import AppKit

// MARK: - Font Registration

/// Registers custom Geist fonts on app startup
enum FontRegistration {
    static var isRegistered = false

    static func registerFonts() {
        guard !isRegistered else { return }

        let fontNames = [
            "Geist-Regular",
            "Geist-Medium",
            "Geist-SemiBold",
            "Geist-Bold",
            "Geist-Light",
            "GeistMono-Regular",
            "GeistMono-Medium",
            "GeistMono-SemiBold",
            "GeistMono-Bold",
            "GeistMono-Light"
        ]

        for fontName in fontNames {
            if let fontURL = Bundle.main.url(forResource: fontName, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
            }
        }

        isRegistered = true
    }
}

// MARK: - Geist Font Helper

enum GeistFont {
    /// Creates a Geist Sans font, falling back to system font if not available
    static func sans(size: CGFloat, weight: Font.Weight) -> Font {
        FontRegistration.registerFonts()

        let fontName: String
        switch weight {
        case .light:
            fontName = "Geist-Light"
        case .regular:
            fontName = "Geist-Regular"
        case .medium:
            fontName = "Geist-Medium"
        case .semibold:
            fontName = "Geist-SemiBold"
        case .bold, .heavy, .black:
            fontName = "Geist-Bold"
        default:
            fontName = "Geist-Regular"
        }

        // Try custom font, fall back to system
        if NSFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        }
        return Font.system(size: size, weight: weight, design: .default)
    }

    /// Creates a Geist Mono font, falling back to system monospaced if not available
    static func mono(size: CGFloat, weight: Font.Weight) -> Font {
        FontRegistration.registerFonts()

        let fontName: String
        switch weight {
        case .light:
            fontName = "GeistMono-Light"
        case .regular:
            fontName = "GeistMono-Regular"
        case .medium:
            fontName = "GeistMono-Medium"
        case .semibold:
            fontName = "GeistMono-SemiBold"
        case .bold, .heavy, .black:
            fontName = "GeistMono-Bold"
        default:
            fontName = "GeistMono-Regular"
        }

        // Try custom font, fall back to system monospaced
        if NSFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        }
        return Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Typography

enum Typography {
    // MARK: - Display

    /// 30pt Light - Large feature headlines (onboarding)
    static let displayLight = GeistFont.sans(size: FontSize.display, weight: .light)

    /// 28pt Light - Feature headlines
    static let headline = GeistFont.sans(size: 28, weight: .light)

    // MARK: - Headings

    /// 24pt Bold - Page titles
    static let h1 = GeistFont.sans(size: FontSize.xxxl, weight: .bold)

    /// 24pt Semibold - Large titles (replaces .title)
    static let title = GeistFont.sans(size: FontSize.xxxl, weight: .semibold)

    /// 20pt Semibold - Section headers
    static let h2 = GeistFont.sans(size: FontSize.xxl, weight: .semibold)

    /// 20pt Bold - Subsection titles (replaces .title2)
    static let title2 = GeistFont.sans(size: FontSize.xxl, weight: .bold)

    /// 18pt Semibold - Subsection headers
    static let h3 = GeistFont.sans(size: FontSize.xl, weight: .semibold)

    /// 18pt Bold - Small titles (replaces .title3)
    static let title3 = GeistFont.sans(size: FontSize.xl, weight: .bold)

    /// 16pt Medium - Card titles
    static let h4 = GeistFont.sans(size: FontSize.lg, weight: .medium)

    // MARK: - Body Text

    /// 14pt Regular - Default body text
    static let body = GeistFont.sans(size: FontSize.base, weight: .regular)

    /// 14pt Medium - Emphasized body text
    static let bodyMedium = GeistFont.sans(size: FontSize.base, weight: .medium)

    /// 13pt Regular - Smaller body text
    static let bodySmall = GeistFont.sans(size: FontSize.smMd, weight: .regular)

    // MARK: - UI Elements

    /// 12pt Medium - Labels, buttons
    static let label = GeistFont.sans(size: FontSize.sm, weight: .medium)

    /// 12pt Regular - Secondary labels
    static let labelRegular = GeistFont.sans(size: FontSize.sm, weight: .regular)

    /// 11pt Regular - Captions, hints
    static let caption = GeistFont.sans(size: FontSize.xs, weight: .regular)

    /// 11pt Medium - Badges, tags
    static let captionMedium = GeistFont.sans(size: FontSize.xs, weight: .medium)

    /// 10pt Regular - Extra small text
    static let micro = GeistFont.sans(size: FontSize.xxs, weight: .regular)

    // MARK: - Code/Terminal (Geist Mono)

    /// 13pt Regular Mono - Code blocks
    static let code = GeistFont.mono(size: FontSize.smMd, weight: .regular)

    /// 12pt Regular Mono - Terminal text
    static let terminal = GeistFont.mono(size: FontSize.sm, weight: .regular)

    /// 11pt Regular Mono - Monospace for hashes, IDs
    static let mono = GeistFont.mono(size: FontSize.xs, weight: .regular)

    // MARK: - Special

    /// 14pt Semibold - Navigation items
    static let nav = GeistFont.sans(size: FontSize.base, weight: .semibold)

    /// 12pt Semibold - Tab labels
    static let tab = GeistFont.sans(size: FontSize.sm, weight: .semibold)
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
