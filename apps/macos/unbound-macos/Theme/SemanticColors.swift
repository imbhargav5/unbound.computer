//
//  SemanticColors.swift
//  unbound-macos
//
//  Shadcn-inspired Zinc color palette with semantic naming
//

import SwiftUI

// MARK: - Shadcn Colors

struct ShadcnColors {
    // Environment to detect color scheme
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Zinc Palette (Raw Values)

    private enum Zinc {
        static let _50 = Color(hex: "fafafa")
        static let _100 = Color(hex: "f4f4f5")
        static let _200 = Color(hex: "e4e4e7")
        static let _300 = Color(hex: "d4d4d8")
        static let _400 = Color(hex: "a1a1aa")
        static let _500 = Color(hex: "71717a")
        static let _600 = Color(hex: "52525b")
        static let _700 = Color(hex: "3f3f46")
        static let _800 = Color(hex: "27272a")
        static let _900 = Color(hex: "18181b")
        static let _950 = Color(hex: "09090b")
    }

    // MARK: - Semantic Colors (Static for simplicity)

    // These are designed for dark mode by default (dev tool aesthetic)
    // Light mode variants provided as well

    struct Dark {
        static let background = Zinc._950
        static let foreground = Zinc._50

        static let card = Zinc._900
        static let cardForeground = Zinc._50

        static let popover = Zinc._900
        static let popoverForeground = Zinc._50

        static let primary = Zinc._50
        static let primaryForeground = Zinc._900

        static let secondary = Zinc._800
        static let secondaryForeground = Zinc._50

        static let muted = Zinc._800
        static let mutedForeground = Zinc._400

        static let accent = Zinc._800
        static let accentForeground = Zinc._50

        static let destructive = Color(hex: "ef4444")
        static let destructiveForeground = Zinc._50

        static let border = Zinc._700
        static let input = Zinc._800
        static let ring = Zinc._300

        // Sidebar text hierarchy (foreground → sidebarText → sidebarMeta → mutedForeground)
        static let sidebarText = Zinc._200          // Session titles, main content
        static let sidebarMeta = Zinc._500          // Metadata, counts, timestamps

        // Additional semantic colors
        static let success = Color(hex: "22c55e")
        static let warning = Color(hex: "eab308")
        static let info = Color(hex: "3b82f6")

        // Surface hierarchy (layered backgrounds for depth)
        static let surface0 = Zinc._950  // Window/root background
        static let surface1 = Zinc._900  // Primary content areas
        static let surface2 = Zinc._800  // Elevated/nested content

        // Primary action color (blue for CTAs that need to stand out from Zinc)
        static let primaryAction = Color(hex: "3b82f6")
        static let primaryActionForeground = Zinc._50
    }

    struct Light {
        static let background = Color.white
        static let foreground = Zinc._950

        static let card = Color.white
        static let cardForeground = Zinc._950

        static let popover = Color.white
        static let popoverForeground = Zinc._950

        static let primary = Zinc._900
        static let primaryForeground = Zinc._50

        static let secondary = Zinc._100
        static let secondaryForeground = Zinc._900

        static let muted = Zinc._100
        static let mutedForeground = Zinc._500

        static let accent = Zinc._100
        static let accentForeground = Zinc._900

        static let destructive = Color(hex: "ef4444")
        static let destructiveForeground = Zinc._50

        static let border = Zinc._200
        static let input = Zinc._200
        static let ring = Zinc._950

        // Sidebar text hierarchy (foreground → sidebarText → sidebarMeta → mutedForeground)
        static let sidebarText = Zinc._700          // Session titles, main content
        static let sidebarMeta = Zinc._400          // Metadata, counts, timestamps

        // Additional semantic colors
        static let success = Color(hex: "22c55e")
        static let warning = Color(hex: "eab308")
        static let info = Color(hex: "3b82f6")

        // Surface hierarchy (layered backgrounds for depth)
        static let surface0 = Color.white        // Window/root background
        static let surface1 = Zinc._50           // Primary content areas
        static let surface2 = Zinc._100          // Elevated/nested content

        // Primary action color (blue for CTAs that need to stand out from Zinc)
        static let primaryAction = Color(hex: "3b82f6")
        static let primaryActionForeground = Color.white
    }
}

// MARK: - Color Scheme Aware Colors

struct ThemeColors {
    let colorScheme: ColorScheme

    init(_ colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }

    var background: Color {
        colorScheme == .dark ? ShadcnColors.Dark.background : ShadcnColors.Light.background
    }

    var foreground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.foreground : ShadcnColors.Light.foreground
    }

    var card: Color {
        colorScheme == .dark ? ShadcnColors.Dark.card : ShadcnColors.Light.card
    }

    var cardForeground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.cardForeground : ShadcnColors.Light.cardForeground
    }

    var primary: Color {
        colorScheme == .dark ? ShadcnColors.Dark.primary : ShadcnColors.Light.primary
    }

    var primaryForeground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.primaryForeground : ShadcnColors.Light.primaryForeground
    }

    var secondary: Color {
        colorScheme == .dark ? ShadcnColors.Dark.secondary : ShadcnColors.Light.secondary
    }

    var secondaryForeground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.secondaryForeground : ShadcnColors.Light.secondaryForeground
    }

    var muted: Color {
        colorScheme == .dark ? ShadcnColors.Dark.muted : ShadcnColors.Light.muted
    }

    var mutedForeground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.mutedForeground : ShadcnColors.Light.mutedForeground
    }

    var accent: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accent : ShadcnColors.Light.accent
    }

    var accentForeground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentForeground : ShadcnColors.Light.accentForeground
    }

    var destructive: Color {
        colorScheme == .dark ? ShadcnColors.Dark.destructive : ShadcnColors.Light.destructive
    }

    var destructiveForeground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.destructiveForeground : ShadcnColors.Light.destructiveForeground
    }

    var border: Color {
        colorScheme == .dark ? ShadcnColors.Dark.border : ShadcnColors.Light.border
    }

    var input: Color {
        colorScheme == .dark ? ShadcnColors.Dark.input : ShadcnColors.Light.input
    }

    var ring: Color {
        colorScheme == .dark ? ShadcnColors.Dark.ring : ShadcnColors.Light.ring
    }

    var success: Color {
        colorScheme == .dark ? ShadcnColors.Dark.success : ShadcnColors.Light.success
    }

    var warning: Color {
        colorScheme == .dark ? ShadcnColors.Dark.warning : ShadcnColors.Light.warning
    }

    var info: Color {
        colorScheme == .dark ? ShadcnColors.Dark.info : ShadcnColors.Light.info
    }

    // Surface hierarchy
    var surface0: Color {
        colorScheme == .dark ? ShadcnColors.Dark.surface0 : ShadcnColors.Light.surface0
    }

    var surface1: Color {
        colorScheme == .dark ? ShadcnColors.Dark.surface1 : ShadcnColors.Light.surface1
    }

    var surface2: Color {
        colorScheme == .dark ? ShadcnColors.Dark.surface2 : ShadcnColors.Light.surface2
    }

    // Primary action color for CTAs
    var primaryAction: Color {
        colorScheme == .dark ? ShadcnColors.Dark.primaryAction : ShadcnColors.Light.primaryAction
    }

    var primaryActionForeground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.primaryActionForeground : ShadcnColors.Light.primaryActionForeground
    }

    // Sidebar text hierarchy
    var sidebarText: Color {
        colorScheme == .dark ? ShadcnColors.Dark.sidebarText : ShadcnColors.Light.sidebarText
    }

    var sidebarMeta: Color {
        colorScheme == .dark ? ShadcnColors.Dark.sidebarMeta : ShadcnColors.Light.sidebarMeta
    }
}

// MARK: - Environment Key

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue = ThemeColors(.dark)
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
