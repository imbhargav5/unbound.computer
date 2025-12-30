//
//  ButtonModifiers.swift
//  rocketry-macos
//
//  Shadcn-style button modifiers
//

import SwiftUI

// MARK: - Button Variant

enum ButtonVariant {
    case primary
    case secondary
    case outline
    case ghost
    case destructive
    case link
}

// MARK: - Button Size

enum ButtonSize {
    case sm
    case md
    case lg
    case icon

    var horizontalPadding: CGFloat {
        switch self {
        case .sm: return Spacing.md
        case .md: return Spacing.lg
        case .lg: return Spacing.xxl
        case .icon: return Spacing.sm
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .sm: return Spacing.xs
        case .md: return Spacing.sm
        case .lg: return Spacing.md
        case .icon: return Spacing.sm
        }
    }

    var font: Font {
        switch self {
        case .sm: return Typography.caption
        case .md: return Typography.label
        case .lg: return Typography.body
        case .icon: return Typography.label
        }
    }
}

// MARK: - Shadcn Button Style

struct ShadcnButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    let variant: ButtonVariant
    let size: ButtonSize

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(borderOverlay)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeInOut(duration: Duration.fast), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let pressedOpacity: Double = 0.9

        switch variant {
        case .primary:
            return isPressed ? colors.primary.opacity(pressedOpacity) : colors.primary
        case .secondary:
            return isPressed ? colors.secondary.opacity(pressedOpacity) : colors.secondary
        case .outline:
            return isPressed ? colors.accent : Color.clear
        case .ghost:
            return isPressed ? colors.accent : Color.clear
        case .destructive:
            return isPressed ? colors.destructive.opacity(pressedOpacity) : colors.destructive
        case .link:
            return Color.clear
        }
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return colors.primaryForeground
        case .secondary:
            return colors.secondaryForeground
        case .outline:
            return isPressed ? colors.accentForeground : colors.foreground
        case .ghost:
            return isPressed ? colors.accentForeground : colors.foreground
        case .destructive:
            return colors.destructiveForeground
        case .link:
            return colors.primary
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch variant {
        case .outline:
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        default:
            EmptyView()
        }
    }
}

// MARK: - View Extensions

extension View {
    func buttonPrimary(size: ButtonSize = .md) -> some View {
        buttonStyle(ShadcnButtonStyle(variant: .primary, size: size))
    }

    func buttonSecondary(size: ButtonSize = .md) -> some View {
        buttonStyle(ShadcnButtonStyle(variant: .secondary, size: size))
    }

    func buttonOutline(size: ButtonSize = .md) -> some View {
        buttonStyle(ShadcnButtonStyle(variant: .outline, size: size))
    }

    func buttonGhost(size: ButtonSize = .md) -> some View {
        buttonStyle(ShadcnButtonStyle(variant: .ghost, size: size))
    }

    func buttonDestructive(size: ButtonSize = .md) -> some View {
        buttonStyle(ShadcnButtonStyle(variant: .destructive, size: size))
    }

    func buttonLink(size: ButtonSize = .md) -> some View {
        buttonStyle(ShadcnButtonStyle(variant: .link, size: size))
    }
}

// MARK: - Icon Button

struct IconButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemName: String
    let variant: ButtonVariant
    let size: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        systemName: String,
        variant: ButtonVariant = .ghost,
        size: CGFloat = IconSize.md,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.variant = variant
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
        }
        .buttonStyle(ShadcnButtonStyle(variant: variant, size: .icon))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
