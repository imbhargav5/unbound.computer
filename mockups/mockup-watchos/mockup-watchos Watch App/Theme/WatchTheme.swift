//
//  WatchTheme.swift
//  mockup-watchos Watch App
//

import SwiftUI

enum WatchTheme {
    // MARK: - Colors

    static let accent = Color.white
    static let accentSecondary = Color.gray

    // Status colors
    static let statusGenerating = Color.green
    static let statusPaused = Color.yellow
    static let statusWaiting = Color.orange
    static let statusCompleted = Color.blue
    static let statusError = Color.red

    // Device status
    static let deviceOnline = Color.green
    static let deviceOffline = Color.gray
    static let deviceBusy = Color.orange

    // Backgrounds
    static let cardBackground = Color.white.opacity(0.1)
    static let buttonBackground = Color.white.opacity(0.15)
    static let dangerBackground = Color.red.opacity(0.2)

    // MARK: - Spacing

    static let spacingXS: CGFloat = 2
    static let spacingS: CGFloat = 4
    static let spacingM: CGFloat = 8
    static let spacingL: CGFloat = 12
    static let spacingXL: CGFloat = 16

    // MARK: - Corner Radius

    static let cornerRadiusSmall: CGFloat = 6
    static let cornerRadiusMedium: CGFloat = 10
    static let cornerRadiusLarge: CGFloat = 14

    // MARK: - Icon Sizes

    static let iconSizeSmall: CGFloat = 12
    static let iconSizeMedium: CGFloat = 16
    static let iconSizeLarge: CGFloat = 24
    static let iconSizeXL: CGFloat = 32
}

// MARK: - View Modifiers

struct WatchCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(WatchTheme.spacingM)
            .background(WatchTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: WatchTheme.cornerRadiusMedium))
    }
}

struct WatchButtonStyle: ViewModifier {
    var color: Color = WatchTheme.buttonBackground

    func body(content: Content) -> some View {
        content
            .padding(WatchTheme.spacingM)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: WatchTheme.cornerRadiusMedium))
    }
}

extension View {
    func watchCardStyle() -> some View {
        modifier(WatchCardStyle())
    }

    func watchButtonStyle(color: Color = WatchTheme.buttonBackground) -> some View {
        modifier(WatchButtonStyle(color: color))
    }
}
