//
//  CardModifier.swift
//  unbound-macos
//
//  Shadcn-style card modifiers
//

import SwiftUI

// MARK: - Card Style Modifier

struct CardStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let variant: CardVariant

    enum CardVariant {
        case `default`
        case muted
        case ghost
        case bordered
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
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

        case .muted:
            content
                .background(colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

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
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Standard card with background and border
    func cardStyle() -> some View {
        modifier(CardStyleModifier(variant: .default))
    }

    /// Muted background card without border
    func cardStyleMuted() -> some View {
        modifier(CardStyleModifier(variant: .muted))
    }

    /// Transparent card (just content)
    func cardStyleGhost() -> some View {
        modifier(CardStyleModifier(variant: .ghost))
    }

    /// Border only, no background
    func cardStyleBordered() -> some View {
        modifier(CardStyleModifier(variant: .bordered))
    }
}

// MARK: - Card Container View

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let variant: CardStyleModifier.CardVariant
    @ViewBuilder let content: () -> Content

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        variant: CardStyleModifier.CardVariant = .default,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.content = content
    }

    var body: some View {
        content()
            .padding(Spacing.lg)
            .modifier(CardStyleModifier(variant: variant))
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
