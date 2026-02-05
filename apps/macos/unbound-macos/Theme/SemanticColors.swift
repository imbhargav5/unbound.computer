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
        // Core backgrounds - Amber theme dark palette
        static let background = Color(hex: "0D0D0D")      // Main background
        static let foreground = Color(hex: "FFFFFF")      // Primary text

        static let card = Color(hex: "0A0A0A")            // Sidebar, headers, footers
        static let cardForeground = Color(hex: "FFFFFF")

        static let popover = Color(hex: "0A0A0A")
        static let popoverForeground = Color(hex: "FFFFFF")

        static let primary = Color(hex: "FFFFFF")
        static let primaryForeground = Color(hex: "0D0D0D")

        static let secondary = Color(hex: "1A1A1A")       // Active tabs, buttons
        static let secondaryForeground = Color(hex: "FFFFFF")

        static let muted = Color(hex: "1A1A1A")
        static let mutedForeground = Color(hex: "A3A3A3") // Muted text

        static let accent = Color(hex: "1A1A1A")          // Accent background
        static let accentForeground = Color(hex: "FFFFFF")

        static let destructive = Color(hex: "F85149")     // Deletion/error color
        static let destructiveForeground = Color(hex: "FFFFFF")

        static let border = Color(hex: "1F1F1F")          // Primary borders
        static let input = Color(hex: "111111")           // Input containers
        static let ring = Color(hex: "F59E0B")            // Focus ring - amber

        // Sidebar text hierarchy (foreground → sidebarText → sidebarMeta → mutedForeground)
        static let sidebarText = Color(hex: "E5E5E5")     // Secondary text
        static let sidebarMeta = Color(hex: "6B6B6B")     // Muted labels

        // Additional semantic colors
        static let success = Color(hex: "22C55E")
        static let warning = Color(hex: "F59E0B")         // Amber for warning
        static let info = Color(hex: "3b82f6")

        // Surface hierarchy (layered backgrounds for depth)
        static let surface0 = Color(hex: "0D0D0D")        // Window/root background
        static let surface1 = Color(hex: "0A0A0A")        // Primary content areas
        static let surface2 = Color(hex: "111111")        // Elevated/nested content

        // Primary action color - AMBER accent
        static let primaryAction = Color(hex: "F59E0B")   // Amber accent
        static let primaryActionForeground = Color(hex: "0D0D0D")

        // MARK: - Amber Accent Variants
        static let accentAmber = Color(hex: "F59E0B")
        static let accentAmberMuted = Color(hex: "F59E0B20")    // 20% opacity
        static let accentAmberSubtle = Color(hex: "F59E0B15")   // 15% opacity
        static let accentAmberBorder = Color(hex: "F59E0B40")   // 40% opacity
        static let accentAmberHalf = Color(hex: "F59E0B50")     // 50% for connectors

        // MARK: - Extended Gray Palette
        static let gray333 = Color(hex: "333333")         // Button backgrounds
        static let gray404 = Color(hex: "404040")         // UI elements
        static let gray4A4 = Color(hex: "4A4A4A")         // Icons
        static let gray525 = Color(hex: "525252")         // Muted elements
        static let gray5A5 = Color(hex: "5A5A5A")         // Inactive icons
        static let gray666 = Color(hex: "666666")         // UI elements
        static let gray7A7 = Color(hex: "7A7A7A")         // Icons, placeholder
        static let gray8A8 = Color(hex: "8A8A8A")         // Icons

        // MARK: - Git/Diff Colors
        static let fileModified = Color(hex: "E2C08D")    // Gold for M status
        static let fileUntracked = Color(hex: "73C991")   // Green for U status
        static let diffAddition = Color(hex: "3FB950")    // Green for +
        static let diffDeletion = Color(hex: "F85149")    // Red for -

        // MARK: - Chat-specific
        static let chatBackground = Color(hex: "0F0F0F")  // Chat panel background

        // MARK: - Border Variants
        static let borderSecondary = Color(hex: "252525") // Terminal border
        static let borderInput = Color(hex: "2A2A2A")     // Input borders
        static let borderButton = Color(hex: "333333")    // Button borders
        static let borderUI = Color(hex: "3A3A3A")        // UI borders

        // MARK: - Text Color Variants
        static let textSecondary = Color(hex: "E5E5E5")   // Secondary text
        static let textMuted = Color(hex: "B3B3B3")       // File names
        static let textInactive = Color(hex: "8A8A8A")    // Inactive text
        static let placeholder = Color(hex: "7A7A7A")     // Placeholder text
        static let textDimmed = Color(hex: "737373")      // Dimmed file paths
        static let inactive = Color(hex: "5A5A5A")        // Inactive tabs
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

    // MARK: - Amber Accent Colors

    var accentAmber: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentAmber : ShadcnColors.Light.primaryAction
    }

    var accentAmberMuted: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentAmberMuted : ShadcnColors.Light.primaryAction.opacity(0.2)
    }

    var accentAmberSubtle: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentAmberSubtle : ShadcnColors.Light.primaryAction.opacity(0.15)
    }

    var accentAmberBorder: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentAmberBorder : ShadcnColors.Light.primaryAction.opacity(0.4)
    }

    var accentAmberHalf: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentAmberHalf : ShadcnColors.Light.primaryAction.opacity(0.5)
    }

    // MARK: - Git/Diff Colors

    var fileModified: Color {
        colorScheme == .dark ? ShadcnColors.Dark.fileModified : Color(hex: "B8860B")
    }

    var fileUntracked: Color {
        colorScheme == .dark ? ShadcnColors.Dark.fileUntracked : Color(hex: "228B22")
    }

    var diffAddition: Color {
        colorScheme == .dark ? ShadcnColors.Dark.diffAddition : Color(hex: "228B22")
    }

    var diffDeletion: Color {
        colorScheme == .dark ? ShadcnColors.Dark.diffDeletion : Color(hex: "DC143C")
    }

    // MARK: - Extended UI Colors

    var chatBackground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.chatBackground : ShadcnColors.Light.background
    }

    var borderSecondary: Color {
        colorScheme == .dark ? ShadcnColors.Dark.borderSecondary : ShadcnColors.Light.border
    }

    var borderInput: Color {
        colorScheme == .dark ? ShadcnColors.Dark.borderInput : ShadcnColors.Light.input
    }

    var placeholder: Color {
        colorScheme == .dark ? ShadcnColors.Dark.placeholder : Color(hex: "9CA3AF")
    }

    var inactive: Color {
        colorScheme == .dark ? ShadcnColors.Dark.inactive : Color(hex: "9CA3AF")
    }

    var gray333: Color {
        colorScheme == .dark ? ShadcnColors.Dark.gray333 : Color(hex: "E5E5E5")
    }

    var textSecondary: Color {
        colorScheme == .dark ? ShadcnColors.Dark.textSecondary : ShadcnColors.Light.sidebarText
    }

    var textMuted: Color {
        colorScheme == .dark ? ShadcnColors.Dark.textMuted : Color(hex: "6B7280")
    }

    var textInactive: Color {
        colorScheme == .dark ? ShadcnColors.Dark.textInactive : Color(hex: "9CA3AF")
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
