//
//  CardModifier.swift
//  mockup-macos
//
//  Shadcn-style card modifiers
//

import SwiftUI

// MARK: - Card Style Modifier

struct CardStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let variant: CardVariant
    let elevation: ElevationValue

    enum CardVariant {
        case `default`
        case muted
        case ghost
        case bordered
        case glass
        case elevated
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(variant: CardVariant, elevation: ElevationValue = Elevation.none) {
        self.variant = variant
        self.elevation = elevation
    }

    func body(content: Content) -> some View {
        switch variant {
        case .default:
            content
                .background(colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(colors.border, lineWidth: BorderWidth.default)
                )
                .modifier(ElevationModifier(elevation: elevation))

        case .muted:
            content
                .background(colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .modifier(ElevationModifier(elevation: elevation))

        case .ghost:
            content
                .background(Color.clear)

        case .bordered:
            content
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(colors.border, lineWidth: BorderWidth.default)
                )

        case .glass:
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(colors.border.opacity(0.5), lineWidth: BorderWidth.hairline)
                )
                .modifier(ElevationModifier(elevation: elevation))

        case .elevated:
            content
                .background(colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .modifier(ElevationModifier(elevation: elevation == Elevation.none ? Elevation.md : elevation))
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Standard card with background and border
    func cardStyle(elevation: ElevationValue = Elevation.none) -> some View {
        modifier(CardStyleModifier(variant: .default, elevation: elevation))
    }

    /// Muted background card without border
    func cardStyleMuted(elevation: ElevationValue = Elevation.none) -> some View {
        modifier(CardStyleModifier(variant: .muted, elevation: elevation))
    }

    /// Transparent card (just content)
    func cardStyleGhost() -> some View {
        modifier(CardStyleModifier(variant: .ghost))
    }

    /// Border only, no background
    func cardStyleBordered() -> some View {
        modifier(CardStyleModifier(variant: .bordered))
    }

    /// Glass/frosted card using ultraThinMaterial
    func cardStyleGlass(elevation: ElevationValue = Elevation.sm) -> some View {
        modifier(CardStyleModifier(variant: .glass, elevation: elevation))
    }

    /// Elevated card with shadow (no border)
    func cardStyleElevated(elevation: ElevationValue = Elevation.md) -> some View {
        modifier(CardStyleModifier(variant: .elevated, elevation: elevation))
    }
}

// MARK: - Card Container View

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let variant: CardStyleModifier.CardVariant
    let elevation: ElevationValue
    @ViewBuilder let content: () -> Content

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        variant: CardStyleModifier.CardVariant = .default,
        elevation: ElevationValue = Elevation.none,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.elevation = elevation
        self.content = content
    }

    var body: some View {
        content()
            .padding(Spacing.lg)
            .modifier(CardStyleModifier(variant: variant, elevation: elevation))
    }
}

// MARK: - Card Header

struct CardHeader<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.bottom, Spacing.sm)
    }
}

// MARK: - Card Content

struct CardContent<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

// MARK: - Card Footer

struct CardFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.top, Spacing.sm)
    }
}
