//
//  CommonModifiers.swift
//  rocketry-macos
//
//  Common shadcn-style modifiers
//

import SwiftUI

// MARK: - Surface Background

struct SurfaceBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let variant: SurfaceVariant

    enum SurfaceVariant {
        case background
        case card
        case muted
        case popover
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
    }

    private var backgroundColor: Color {
        switch variant {
        case .background:
            return colors.background
        case .card:
            return colors.card
        case .muted:
            return colors.muted
        case .popover:
            return colors.card
        }
    }
}

// MARK: - Border Style

struct BorderStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let radius: CGFloat
    let width: CGFloat

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(colors.border, lineWidth: width)
            )
    }
}

// MARK: - Hover Effect

struct HoverEffectModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    func body(content: Content) -> some View {
        content
            .background(isHovering ? colors.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: Duration.fast)) {
                    isHovering = hovering
                }
            }
    }
}

// MARK: - Selection State

struct SelectionModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let isSelected: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    func body(content: Content) -> some View {
        content
            .background(isSelected ? colors.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Divider Style

struct ShadcnDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    let orientation: Orientation

    enum Orientation {
        case horizontal
        case vertical
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(_ orientation: Orientation = .horizontal) {
        self.orientation = orientation
    }

    var body: some View {
        switch orientation {
        case .horizontal:
            Rectangle()
                .fill(colors.border)
                .frame(height: BorderWidth.default)
        case .vertical:
            Rectangle()
                .fill(colors.border)
                .frame(width: BorderWidth.default)
        }
    }
}

// MARK: - Badge

struct Badge: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let variant: BadgeVariant

    enum BadgeVariant {
        case `default`
        case secondary
        case destructive
        case outline
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(_ text: String, variant: BadgeVariant = .default) {
        self.text = text
        self.variant = variant
    }

    var body: some View {
        Text(text)
            .font(Typography.micro)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: Radius.full))
            .overlay(borderOverlay)
    }

    private var backgroundColor: Color {
        switch variant {
        case .default:
            return colors.primary
        case .secondary:
            return colors.secondary
        case .destructive:
            return colors.destructive
        case .outline:
            return Color.clear
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .default:
            return colors.primaryForeground
        case .secondary:
            return colors.secondaryForeground
        case .destructive:
            return colors.destructiveForeground
        case .outline:
            return colors.foreground
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if variant == .outline {
            RoundedRectangle(cornerRadius: Radius.full)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        }
    }
}

// MARK: - View Extensions

extension View {
    func surfaceBackground(_ variant: SurfaceBackgroundModifier.SurfaceVariant = .background) -> some View {
        modifier(SurfaceBackgroundModifier(variant: variant))
    }

    func borderStyle(radius: CGFloat = Radius.md, width: CGFloat = BorderWidth.default) -> some View {
        modifier(BorderStyleModifier(radius: radius, width: width))
    }

    func hoverEffect() -> some View {
        modifier(HoverEffectModifier())
    }

    func selectionStyle(isSelected: Bool) -> some View {
        modifier(SelectionModifier(isSelected: isSelected))
    }
}
