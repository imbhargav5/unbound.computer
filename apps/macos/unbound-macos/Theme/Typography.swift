//
//  Typography.swift
//  unbound-macos
//
//  Geist typography system for dev-tool aesthetic
//  Supports dynamic scaling via LocalSettings font size preset
//

import SwiftUI
import AppKit
import CoreText

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
    /// Creates a Geist Sans font with scaling support, falling back to system font if not available
    @MainActor
    static func sans(size: CGFloat, weight: Font.Weight) -> Font {
        FontRegistration.registerFonts()
        let scaledSize = LocalSettings.shared.scaled(size)

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
        if NSFont(name: fontName, size: scaledSize) != nil {
            return Font.custom(fontName, size: scaledSize)
        }
        return Font.system(size: scaledSize, weight: weight, design: .default)
    }

    /// Creates a Geist Mono font with scaling support, falling back to system monospaced if not available
    @MainActor
    static func mono(size: CGFloat, weight: Font.Weight) -> Font {
        FontRegistration.registerFonts()
        let scaledSize = LocalSettings.shared.scaled(size)

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
        if NSFont(name: fontName, size: scaledSize) != nil {
            return Font.custom(fontName, size: scaledSize)
        }
        return Font.system(size: scaledSize, weight: weight, design: .monospaced)
    }
}

// MARK: - Typography

enum Typography {
    // MARK: - Display

    /// Display Light - Large feature headlines (onboarding)
    @MainActor
    static var displayLight: Font {
        GeistFont.sans(size: FontSize.display, weight: .light)
    }

    /// Headline Light - Feature headlines
    @MainActor
    static var headline: Font {
        GeistFont.sans(size: 26, weight: .light)
    }

    // MARK: - Headings

    /// Bold - Page titles
    @MainActor
    static var h1: Font {
        GeistFont.sans(size: FontSize.xxxl, weight: .bold)
    }

    /// Semibold - Large titles (replaces .title)
    @MainActor
    static var title: Font {
        GeistFont.sans(size: FontSize.xxxl, weight: .semibold)
    }

    /// Semibold - Section headers
    @MainActor
    static var h2: Font {
        GeistFont.sans(size: FontSize.xxl, weight: .semibold)
    }

    /// Bold - Subsection titles (replaces .title2)
    @MainActor
    static var title2: Font {
        GeistFont.sans(size: FontSize.xxl, weight: .bold)
    }

    /// Semibold - Subsection headers
    @MainActor
    static var h3: Font {
        GeistFont.sans(size: FontSize.xl, weight: .semibold)
    }

    /// Bold - Small titles (replaces .title3)
    @MainActor
    static var title3: Font {
        GeistFont.sans(size: FontSize.xl, weight: .bold)
    }

    /// Medium - Card titles
    @MainActor
    static var h4: Font {
        GeistFont.sans(size: FontSize.lg, weight: .medium)
    }

    // MARK: - Body Text

    /// Regular - Default body text
    @MainActor
    static var body: Font {
        GeistFont.sans(size: FontSize.base, weight: .regular)
    }

    /// Medium - Emphasized body text
    @MainActor
    static var bodyMedium: Font {
        GeistFont.sans(size: FontSize.base, weight: .medium)
    }

    /// Regular - Smaller body text
    @MainActor
    static var bodySmall: Font {
        GeistFont.sans(size: FontSize.smMd, weight: .regular)
    }

    // MARK: - UI Elements

    /// Medium - Labels, buttons
    @MainActor
    static var label: Font {
        GeistFont.sans(size: FontSize.sm, weight: .medium)
    }

    /// Regular - Secondary labels
    @MainActor
    static var labelRegular: Font {
        GeistFont.sans(size: FontSize.sm, weight: .regular)
    }

    /// Regular - Captions, hints
    @MainActor
    static var caption: Font {
        GeistFont.sans(size: FontSize.xs, weight: .regular)
    }

    /// Medium - Badges, tags
    @MainActor
    static var captionMedium: Font {
        GeistFont.sans(size: FontSize.xs, weight: .medium)
    }

    /// Regular - Extra small text
    @MainActor
    static var micro: Font {
        GeistFont.sans(size: FontSize.xxs, weight: .regular)
    }

    // MARK: - Code/Terminal (Geist Mono)

    /// Regular Mono - Code blocks
    @MainActor
    static var code: Font {
        GeistFont.mono(size: FontSize.smMd, weight: .regular)
    }

    /// Regular Mono - Terminal text
    @MainActor
    static var terminal: Font {
        GeistFont.mono(size: FontSize.sm, weight: .regular)
    }

    /// Regular Mono - Monospace for hashes, IDs
    @MainActor
    static var mono: Font {
        GeistFont.mono(size: FontSize.xs, weight: .regular)
    }

    // MARK: - Special

    /// Semibold - Navigation items
    @MainActor
    static var nav: Font {
        GeistFont.sans(size: FontSize.base, weight: .semibold)
    }

    /// Semibold - Tab labels
    @MainActor
    static var tab: Font {
        GeistFont.sans(size: FontSize.sm, weight: .semibold)
    }
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
        if let color {
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
