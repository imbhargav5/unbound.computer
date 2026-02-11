import SwiftUI
import UIKit
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
        if UIFont(name: fontName, size: size) != nil {
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
        if UIFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        }
        return Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Typography

enum Typography {
    // Display
    static let largeTitle = GeistFont.sans(size: 34, weight: .bold)
    static let title = GeistFont.sans(size: 28, weight: .bold)
    static let title2 = GeistFont.sans(size: 22, weight: .bold)
    static let title3 = GeistFont.sans(size: 20, weight: .semibold)

    // Body
    static let headline = GeistFont.sans(size: 17, weight: .semibold)
    static let body = GeistFont.sans(size: 17, weight: .regular)
    static let callout = GeistFont.sans(size: 16, weight: .regular)
    static let subheadline = GeistFont.sans(size: 15, weight: .regular)
    static let footnote = GeistFont.sans(size: 13, weight: .regular)
    static let caption = GeistFont.sans(size: 12, weight: .regular)
    static let caption2 = GeistFont.sans(size: 11, weight: .regular)

    // Code
    static let code = GeistFont.mono(size: 14, weight: .regular)
    static let codeSmall = GeistFont.mono(size: 12, weight: .regular)
}

enum AppTheme {
    // MARK: - Primary Accent (Black & White theme)
    static let accent = Color(.label)
    static let accentSecondary = Color(.secondaryLabel)

    // MARK: - Claude Brand Colors (for Claude avatar/branding only)
    static let claudeOrange = Color(red: 224/255, green: 122/255, blue: 95/255)  // #E07A5F
    static let claudeCoral = Color(red: 242/255, green: 153/255, blue: 74/255)   // #F2994A
    static let claudeTan = Color(red: 212/255, green: 165/255, blue: 116/255)    // #D4A574

    // MARK: - Gradients
    static let claudeGradient = LinearGradient(
        colors: [claudeOrange, claudeCoral],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [Color(.label), Color(.label).opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.15),
            Color.white.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic Colors
    static let backgroundPrimary = Color(.systemBackground)
    static let backgroundSecondary = Color(.secondarySystemBackground)
    static let backgroundTertiary = Color(.tertiarySystemBackground)

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let cardBackground = Color(.secondarySystemBackground)
    static let cardBorder = Color(.separator)

    // MARK: - Status Colors
    static let statusOnline = Color.green
    static let statusOffline = Color.gray
    static let statusBusy = Color.orange

    // MARK: - Message Colors
    static let userBubbleBackground = Color(UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.19, green: 0.13, blue: 0.04, alpha: 1.0)
        default:
            return UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 1.0)
        }
    })

    static let userBubbleBorder = Color(UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.42, green: 0.30, blue: 0.09, alpha: 1.0)
        default:
            return UIColor(red: 0.82, green: 0.68, blue: 0.40, alpha: 1.0)
        }
    })

    static let userBubbleText = Color(UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 1.0)
        default:
            return UIColor(red: 0.22, green: 0.16, blue: 0.08, alpha: 1.0)
        }
    })

    static let userBubbleTimestamp = Color(UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.70, green: 0.57, blue: 0.34, alpha: 1.0)
        default:
            return UIColor(red: 0.44, green: 0.33, blue: 0.18, alpha: 1.0)
        }
    })

    static let userBubble = userBubbleBackground
    static let assistantBubble = Color(.tertiarySystemBackground)

    // MARK: - Diff Colors
    static let diffAdditionBg = Color.green.opacity(0.15)
    static let diffDeletionBg = Color.red.opacity(0.15)
    static let diffAdditionText = Color.green
    static let diffDeletionText = Color.red
    static let diffContextText = Color.gray
    static let diffBackground = Color(white: 0.12)
    static let diffHeaderBg = Color.black.opacity(0.4)

    // MARK: - Tool Badge Colors
    static let toolBadgeBg = Color(.label).opacity(0.1)

    // MARK: - Corner Radii
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    static let cornerRadiusXLarge: CGFloat = 24

    // MARK: - Spacing
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: - Shadows
    static let cardShadowColor = Color.black.opacity(0.08)
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowY: CGFloat = 2

    // MARK: - Device Home Accent
    static let amberAccent = Color(red: 232/255, green: 167/255, blue: 62/255)  // #E8A73E
    static let deviceCardBackground = Color(white: 0.08)
    static let thinBorderWidth: CGFloat = 1.0
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
            .shadow(
                color: AppTheme.cardShadowColor,
                radius: AppTheme.cardShadowRadius,
                x: 0,
                y: AppTheme.cardShadowY
            )
    }
}

struct ThinBorderCardStyle: ViewModifier {
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .background(AppTheme.deviceCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(
                        highlighted ? AppTheme.amberAccent.opacity(0.6) : Color.white.opacity(0.1),
                        lineWidth: AppTheme.thinBorderWidth
                    )
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func thinBorderCard(highlighted: Bool = false) -> some View {
        modifier(ThinBorderCardStyle(highlighted: highlighted))
    }
}
