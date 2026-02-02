import SwiftUI
import UIKit

enum AppTheme {
    // MARK: - Primary Accent (Black & White theme)
    static let accent = Color(UIColor.label)
    static let accentSecondary = Color(UIColor.secondaryLabel)

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
        colors: [Color(UIColor.label), Color(UIColor.label).opacity(0.8)],
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
    static let backgroundPrimary = Color(UIColor.systemBackground)
    static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
    static let backgroundTertiary = Color(UIColor.tertiarySystemBackground)

    static let textPrimary = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let textTertiary = Color(UIColor.tertiaryLabel)

    static let cardBackground = Color(UIColor.secondarySystemBackground)
    static let cardBorder = Color(UIColor.separator)

    // MARK: - Status Colors
    static let statusOnline = Color.green
    static let statusOffline = Color.gray
    static let statusBusy = Color.orange

    // MARK: - Message Colors
    static let userBubble = Color(UIColor.label)
    static let assistantBubble = Color(UIColor.tertiarySystemBackground)

    // MARK: - Diff Colors
    static let diffAdditionBg = Color.green.opacity(0.15)
    static let diffDeletionBg = Color.red.opacity(0.15)
    static let diffAdditionText = Color.green
    static let diffDeletionText = Color.red
    static let diffContextText = Color.gray
    static let diffBackground = Color(white: 0.12)
    static let diffHeaderBg = Color.black.opacity(0.4)

    // MARK: - Tool Badge Colors
    static let toolBadgeBg = Color(UIColor.label).opacity(0.1)

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

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
