//
//  SemanticColors.swift
//  unbound-macos
//
//  Amber/gray palette with semantic naming
//

import SwiftUI

// MARK: - Shadcn Colors

struct ShadcnColors {
    // Environment to detect color scheme
    @Environment(\.colorScheme) private var colorScheme

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

        static let primary = Color(hex: "F59E0B")
        static let primaryForeground = Color(hex: "0D0D0D")

        static let secondary = Color(hex: "1A1A1A")       // Active tabs, buttons
        static let secondaryForeground = Color(hex: "FFFFFF")

        static let muted = Color(hex: "111111")
        static let mutedForeground = Color(hex: "A3A3A3") // Muted text

        static let accent = Color(hex: "F59E0B15")        // Accent background
        static let accentForeground = Color(hex: "FFFFFF")

        static let destructive = Color(hex: "F59E0B")     // Deletion/error color (amber)
        static let destructiveForeground = Color(hex: "0D0D0D")

        static let border = Color(hex: "1F1F1F")          // Primary borders
        static let input = Color(hex: "111111")           // Input containers
        static let ring = Color(hex: "F59E0B")            // Focus ring - amber

        // Sidebar text hierarchy (foreground → sidebarText → sidebarMeta → mutedForeground)
        static let sidebarText = Color(hex: "E5E5E5")     // Secondary text
        static let sidebarMeta = Color(hex: "6B6B6B")     // Muted labels

        // Additional semantic colors
        static let success = Color(hex: "22C55E")
        static let warning = Color(hex: "F59E0B")         // Amber for warning
        static let info = Color(hex: "F59E0B")

        // Surface hierarchy (layered backgrounds for depth)
        static let surface0 = Color(hex: "0D0D0D")        // Window/root background
        static let surface1 = Color(hex: "0F0F0F")        // Primary content areas
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

        // MARK: - Green Accent Variants (Explore Agent)
        static let accentGreen = Color(hex: "22C55E")
        static let accentGreenMuted = Color(hex: "22C55E20")    // 20% opacity
        static let accentGreenSubtle = Color(hex: "22C55E15")   // 15% opacity

        // MARK: - Purple Accent Variants (Plan Agent)
        static let accentPurple = Color(hex: "A855F7")
        static let accentPurpleMuted = Color(hex: "A855F720")   // 20% opacity
        static let accentPurpleSubtle = Color(hex: "A855F715")  // 15% opacity

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
        static let diffDeletion = Color(hex: "F59E0B")    // Amber for -

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

        // MARK: - Workspace-Specific UI
        static let toolbarBackground = Color(hex: "0F0F0F")
        static let panelDivider = Color(hex: "1A1A1A")
        static let selectionBackground = Color(hex: "F59E0B15") // 15% amber
        static let selectionBorder = Color(hex: "F59E0B40")     // 40% amber
        static let hoverBackground = Color(hex: "1A1A1A")
        static let editorBackground = Color(hex: "111111")
    }

    struct Light {
        static let background = Color(hex: "FFFFFF")
        static let foreground = Color(hex: "0D0D0D")

        static let card = Color(hex: "FFFFFF")
        static let cardForeground = Color(hex: "0D0D0D")

        static let popover = Color(hex: "FFFFFF")
        static let popoverForeground = Color(hex: "0D0D0D")

        static let primary = Color(hex: "F59E0B")
        static let primaryForeground = Color(hex: "0D0D0D")

        static let secondary = Color(hex: "E5E5E5")
        static let secondaryForeground = Color(hex: "0D0D0D")

        static let muted = Color(hex: "E5E5E5")
        static let mutedForeground = Color(hex: "737373")

        static let accent = Color(hex: "F59E0B15")
        static let accentForeground = Color(hex: "0D0D0D")

        static let destructive = Color(hex: "F59E0B")
        static let destructiveForeground = Color(hex: "0D0D0D")

        static let border = Color(hex: "B3B3B3")
        static let input = Color(hex: "E5E5E5")
        static let ring = Color(hex: "F59E0B")

        // Sidebar text hierarchy (foreground → sidebarText → sidebarMeta → mutedForeground)
        static let sidebarText = Color(hex: "0D0D0D")     // Session titles, main content
        static let sidebarMeta = Color(hex: "737373")     // Metadata, counts, timestamps

        // Additional semantic colors
        static let success = Color(hex: "22C55E")
        static let warning = Color(hex: "F59E0B")
        static let info = Color(hex: "F59E0B")

        // Surface hierarchy (layered backgrounds for depth)
        static let surface0 = Color(hex: "FFFFFF")        // Window/root background
        static let surface1 = Color(hex: "E5E5E5")        // Primary content areas
        static let surface2 = Color(hex: "B3B3B3")        // Elevated/nested content

        // Primary action color
        static let primaryAction = Color(hex: "F59E0B")
        static let primaryActionForeground = Color(hex: "0D0D0D")

        // MARK: - Git/Diff Colors
        static let fileModified = Color(hex: "E2C08D")
        static let fileUntracked = Color(hex: "73C991")
        static let diffAddition = Color(hex: "3FB950")
        static let diffDeletion = Color(hex: "F59E0B")

        // MARK: - Text Color Variants
        static let textSecondary = Color(hex: "0D0D0D")
        static let textMuted = Color(hex: "737373")
        static let textInactive = Color(hex: "8A8A8A")
        static let textDimmed = Color(hex: "737373")
        static let placeholder = Color(hex: "7A7A7A")
        static let inactive = Color(hex: "5A5A5A")

        // MARK: - Extended Gray Palette
        static let gray333 = Color(hex: "E5E5E5")
        static let gray404 = Color(hex: "404040")
        static let gray4A4 = Color(hex: "4A4A4A")
        static let gray525 = Color(hex: "525252")
        static let gray666 = Color(hex: "666666")
        static let gray7A7 = Color(hex: "7A7A7A")
        static let gray8A8 = Color(hex: "8A8A8A")

        // Workspace-specific UI (light defaults)
        static let toolbarBackground = Color(hex: "FFFFFF")
        static let panelDivider = Color(hex: "B3B3B3")
        static let selectionBackground = Color(hex: "F59E0B15")
        static let selectionBorder = Color(hex: "F59E0B40")
        static let hoverBackground = Color(hex: "E5E5E5")
        static let editorBackground = Color(hex: "FFFFFF")
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

    // MARK: - Green Accent Colors (Explore agents)

    var accentGreen: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentGreen : ShadcnColors.Dark.accentGreen
    }

    var accentGreenMuted: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentGreenMuted : ShadcnColors.Dark.accentGreen.opacity(0.2)
    }

    // MARK: - Purple Accent Colors (Plan agents)

    var accentPurple: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentPurple : ShadcnColors.Dark.accentPurple
    }

    var accentPurpleMuted: Color {
        colorScheme == .dark ? ShadcnColors.Dark.accentPurpleMuted : ShadcnColors.Dark.accentPurple.opacity(0.2)
    }

    // MARK: - Git/Diff Colors

    var fileModified: Color {
        colorScheme == .dark ? ShadcnColors.Dark.fileModified : ShadcnColors.Light.fileModified
    }

    var fileUntracked: Color {
        colorScheme == .dark ? ShadcnColors.Dark.fileUntracked : ShadcnColors.Light.fileUntracked
    }

    var diffAddition: Color {
        colorScheme == .dark ? ShadcnColors.Dark.diffAddition : ShadcnColors.Light.diffAddition
    }

    var diffDeletion: Color {
        colorScheme == .dark ? ShadcnColors.Dark.diffDeletion : ShadcnColors.Light.diffDeletion
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
        colorScheme == .dark ? ShadcnColors.Dark.placeholder : ShadcnColors.Light.placeholder
    }

    var inactive: Color {
        colorScheme == .dark ? ShadcnColors.Dark.inactive : ShadcnColors.Light.inactive
    }

    var gray333: Color {
        colorScheme == .dark ? ShadcnColors.Dark.gray333 : ShadcnColors.Light.gray333
    }

    var gray404: Color {
        colorScheme == .dark ? ShadcnColors.Dark.gray404 : ShadcnColors.Light.gray404
    }

    var gray4A4: Color {
        colorScheme == .dark ? ShadcnColors.Dark.gray4A4 : ShadcnColors.Light.gray4A4
    }

    var gray525: Color {
        colorScheme == .dark ? ShadcnColors.Dark.gray525 : ShadcnColors.Light.gray525
    }

    var gray666: Color {
        colorScheme == .dark ? ShadcnColors.Dark.gray666 : ShadcnColors.Light.gray666
    }

    var gray7A7: Color {
        colorScheme == .dark ? ShadcnColors.Dark.gray7A7 : ShadcnColors.Light.gray7A7
    }

    var textSecondary: Color {
        colorScheme == .dark ? ShadcnColors.Dark.textSecondary : ShadcnColors.Light.textSecondary
    }

    var textMuted: Color {
        colorScheme == .dark ? ShadcnColors.Dark.textMuted : ShadcnColors.Light.textMuted
    }

    var textInactive: Color {
        colorScheme == .dark ? ShadcnColors.Dark.textInactive : ShadcnColors.Light.textInactive
    }

    var textDimmed: Color {
        colorScheme == .dark ? ShadcnColors.Dark.textDimmed : ShadcnColors.Light.textDimmed
    }

    var gray8A8: Color {
        colorScheme == .dark ? ShadcnColors.Dark.gray8A8 : ShadcnColors.Light.gray8A8
    }

    // MARK: - Workspace-Specific UI

    var toolbarBackground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.toolbarBackground : ShadcnColors.Light.toolbarBackground
    }

    var panelDivider: Color {
        colorScheme == .dark ? ShadcnColors.Dark.panelDivider : ShadcnColors.Light.panelDivider
    }

    var selectionBackground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.selectionBackground : ShadcnColors.Light.selectionBackground
    }

    var selectionBorder: Color {
        colorScheme == .dark ? ShadcnColors.Dark.selectionBorder : ShadcnColors.Light.selectionBorder
    }

    var hoverBackground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.hoverBackground : ShadcnColors.Light.hoverBackground
    }

    var editorBackground: Color {
        colorScheme == .dark ? ShadcnColors.Dark.editorBackground : ShadcnColors.Light.editorBackground
    }

    // MARK: - Agent Type Colors

    /// Returns the accent color for a given agent type
    func agentAccentColor(for agentType: String) -> Color {
        switch agentType.lowercased() {
        case "explore":
            return accentGreen
        case "plan":
            return accentPurple
        case "bash":
            return accentAmber
        case "general-purpose":
            return accentAmber
        default:
            return accentAmber
        }
    }

    /// Returns the muted background color for a given agent type
    func agentAccentMutedColor(for agentType: String) -> Color {
        switch agentType.lowercased() {
        case "explore":
            return accentGreenMuted
        case "plan":
            return accentPurpleMuted
        case "bash":
            return accentAmberMuted
        case "general-purpose":
            return accentAmberMuted
        default:
            return accentAmberMuted
        }
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
        case 8: // RGBA (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
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
