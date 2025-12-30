//
//  InputModifiers.swift
//  rocketry-macos
//
//  Shadcn-style input field modifiers
//

import SwiftUI

// MARK: - Input Style Modifier

struct InputStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let variant: InputVariant

    enum InputVariant {
        case `default`
        case ghost
        case filled
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    func body(content: Content) -> some View {
        switch variant {
        case .default:
            content
                .font(Typography.body)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(colors.background)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(colors.border, lineWidth: BorderWidth.default)
                )

        case .ghost:
            content
                .font(Typography.body)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.clear)

        case .filled:
            content
                .font(Typography.body)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(colors.input)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Standard input with border
    func inputStyle() -> some View {
        modifier(InputStyleModifier(variant: .default))
    }

    /// Ghost input without background
    func inputStyleGhost() -> some View {
        modifier(InputStyleModifier(variant: .ghost))
    }

    /// Filled input with background
    func inputStyleFilled() -> some View {
        modifier(InputStyleModifier(variant: .filled))
    }
}

// MARK: - Shadcn Text Field

struct ShadcnTextField: View {
    @Environment(\.colorScheme) private var colorScheme

    let placeholder: String
    @Binding var text: String
    let variant: InputStyleModifier.InputVariant

    @FocusState private var isFocused: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        _ placeholder: String,
        text: Binding<String>,
        variant: InputStyleModifier.InputVariant = .default
    ) {
        self.placeholder = placeholder
        self._text = text
        self.variant = variant
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .modifier(InputStyleModifier(variant: variant))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(
                        isFocused ? colors.ring : Color.clear,
                        lineWidth: isFocused ? 2 : 0
                    )
            )
            .animation(.easeInOut(duration: Duration.fast), value: isFocused)
    }
}

// MARK: - Shadcn Text Editor

struct ShadcnTextEditor: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    let variant: InputStyleModifier.InputVariant

    @FocusState private var isFocused: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        text: Binding<String>,
        variant: InputStyleModifier.InputVariant = .default
    ) {
        self._text = text
        self.variant = variant
    }

    var body: some View {
        TextEditor(text: $text)
            .font(Typography.body)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .padding(Spacing.md)
            .background(variant == .filled ? colors.input : colors.background)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(
                        isFocused ? colors.ring : colors.border,
                        lineWidth: BorderWidth.default
                    )
            )
            .animation(.easeInOut(duration: Duration.fast), value: isFocused)
    }
}
