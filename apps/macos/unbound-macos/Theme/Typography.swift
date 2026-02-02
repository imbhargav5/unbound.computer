//
//  Typography.swift
//  unbound-macos
//
//  SF Mono typography system for dev-tool aesthetic
//  Supports dynamic scaling via LocalSettings font size preset
//

import SwiftUI

// MARK: - Typography

enum Typography {
    // MARK: - Scaled Font Helper

    /// Creates a scaled font based on LocalSettings
    @MainActor
    private static func scaledFont(size: CGFloat, weight: Font.Weight, design: Font.Design = .monospaced) -> Font {
        let scaledSize = LocalSettings.shared.scaled(size)
        return Font.system(size: scaledSize, weight: weight, design: design)
    }

    // MARK: - Display

    /// Display Light Mono - Large feature headlines (onboarding)
    @MainActor
    static var displayLight: Font {
        scaledFont(size: FontSize.display, weight: .light)
    }

    /// Headline Light Mono - Feature headlines
    @MainActor
    static var headline: Font {
        scaledFont(size: 26, weight: .light)
    }

    // MARK: - Headings

    /// Bold Mono - Page titles
    @MainActor
    static var h1: Font {
        scaledFont(size: FontSize.xxxl, weight: .bold)
    }

    /// Semibold Mono - Large titles (replaces .title)
    @MainActor
    static var title: Font {
        scaledFont(size: FontSize.xxxl, weight: .semibold)
    }

    /// Semibold Mono - Section headers
    @MainActor
    static var h2: Font {
        scaledFont(size: FontSize.xxl, weight: .semibold)
    }

    /// Bold Mono - Subsection titles (replaces .title2)
    @MainActor
    static var title2: Font {
        scaledFont(size: FontSize.xxl, weight: .bold)
    }

    /// Semibold Mono - Subsection headers
    @MainActor
    static var h3: Font {
        scaledFont(size: FontSize.xl, weight: .semibold)
    }

    /// Bold Mono - Small titles (replaces .title3)
    @MainActor
    static var title3: Font {
        scaledFont(size: FontSize.xl, weight: .bold)
    }

    /// Medium Mono - Card titles
    @MainActor
    static var h4: Font {
        scaledFont(size: FontSize.lg, weight: .medium)
    }

    // MARK: - Body Text

    /// Regular Mono - Default body text
    @MainActor
    static var body: Font {
        scaledFont(size: FontSize.base, weight: .regular)
    }

    /// Medium Mono - Emphasized body text
    @MainActor
    static var bodyMedium: Font {
        scaledFont(size: FontSize.base, weight: .medium)
    }

    /// Regular Mono - Smaller body text
    @MainActor
    static var bodySmall: Font {
        scaledFont(size: FontSize.smMd, weight: .regular)
    }

    // MARK: - UI Elements

    /// Medium Mono - Labels, buttons
    @MainActor
    static var label: Font {
        scaledFont(size: FontSize.sm, weight: .medium)
    }

    /// Regular Mono - Secondary labels
    @MainActor
    static var labelRegular: Font {
        scaledFont(size: FontSize.sm, weight: .regular)
    }

    /// Regular Mono - Captions, hints
    @MainActor
    static var caption: Font {
        scaledFont(size: FontSize.xs, weight: .regular)
    }

    /// Medium Mono - Badges, tags
    @MainActor
    static var captionMedium: Font {
        scaledFont(size: FontSize.xs, weight: .medium)
    }

    /// Regular Mono - Extra small text
    @MainActor
    static var micro: Font {
        scaledFont(size: FontSize.xxs, weight: .regular)
    }

    // MARK: - Code/Terminal

    /// Regular Mono - Code blocks
    @MainActor
    static var code: Font {
        scaledFont(size: FontSize.smMd, weight: .regular)
    }

    /// Regular Mono - Terminal text
    @MainActor
    static var terminal: Font {
        scaledFont(size: FontSize.sm, weight: .regular)
    }

    /// Regular Mono - Monospace for hashes, IDs
    @MainActor
    static var mono: Font {
        scaledFont(size: FontSize.xs, weight: .regular)
    }

    // MARK: - Special

    /// Semibold Mono - Navigation items
    @MainActor
    static var nav: Font {
        scaledFont(size: FontSize.base, weight: .semibold)
    }

    /// Semibold Mono - Tab labels
    @MainActor
    static var tab: Font {
        scaledFont(size: FontSize.sm, weight: .semibold)
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
