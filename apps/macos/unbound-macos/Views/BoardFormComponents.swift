//
//  BoardFormComponents.swift
//  unbound-macos
//
//  Shared board setup and creation form primitives.
//

import SwiftUI

struct BoardOnboardingContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let eyebrow: String
    let title: String
    let message: String
    let contentMaxWidth: CGFloat
    @ViewBuilder let content: () -> Content

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        eyebrow: String,
        title: String,
        message: String,
        contentMaxWidth: CGFloat = 560,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.contentMaxWidth = contentMaxWidth
        self.content = content
    }

    var body: some View {
        ZStack {
            colors.background
                .ignoresSafeArea()

            VStack(spacing: Spacing.xxxl) {
                VStack(spacing: Spacing.md) {
                    BoardEyebrowBadge(text: eyebrow)

                    Text(title)
                        .font(Typography.pageTitle)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(colors.foreground)

                    Text(message)
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 680)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
                    .frame(maxWidth: contentMaxWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 64)
            .padding(.vertical, Spacing.xxxxxl)
        }
    }
}

struct BoardEyebrowBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(colors.primary)
                .frame(width: 6, height: 6)

            Text(text)
                .font(Typography.captionMedium)
                .foregroundStyle(colors.primary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(colors.accent)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(colors.primary.opacity(0.24), lineWidth: BorderWidth.default)
        )
    }
}

struct BoardCardSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let padding: CGFloat
    let elevation: ElevationValue
    @ViewBuilder let content: () -> Content

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        padding: CGFloat = Spacing.xl,
        elevation: ElevationValue = Elevation.md,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.elevation = elevation
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            content()
        }
        .padding(padding)
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
        .elevation(elevation)
    }
}

struct BoardDialogScaffold<Content: View, Footer: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let contentSpacing: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        title: String,
        subtitle: String,
        contentSpacing: CGFloat = Spacing.lg,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.contentSpacing = contentSpacing
        self.content = content
        self.footer = footer
    }

    var body: some View {
        ZStack {
            colors.background
                .ignoresSafeArea()

            BoardCardSurface(padding: Spacing.xl, elevation: Elevation.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(title)
                        .font(Typography.h3)
                        .foregroundStyle(colors.foreground)

                    Text(subtitle)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ShadcnDivider()

                ScrollView {
                    VStack(alignment: .leading, spacing: contentSpacing) {
                        content()
                    }
                }
                .scrollIndicators(.never)

                ShadcnDivider()

                footer()
            }
            .padding(Spacing.xl)
        }
    }
}

struct BoardFormFieldGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let hint: String?
    @ViewBuilder let content: () -> Content

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        label: String,
        hint: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.hint = hint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.captionMedium)
                .foregroundStyle(colors.foreground)

            content()

            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(Typography.micro)
                    .foregroundStyle(colors.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct BoardMultilineInput: View {
    @Environment(\.colorScheme) private var colorScheme

    let placeholder: String
    @Binding var text: String
    let minHeight: CGFloat

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = 92
    ) {
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShadcnTextEditor(text: $text, variant: .filled)
                .frame(minHeight: minHeight)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground.opacity(0.65))
                    .padding(.top, Spacing.md)
                    .padding(.leading, Spacing.md)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct BoardMenuField<MenuContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let valueText: String
    let isPlaceholder: Bool
    @ViewBuilder let menuContent: () -> MenuContent

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        valueText: String,
        isPlaceholder: Bool = false,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.valueText = valueText
        self.isPlaceholder = isPlaceholder
        self.menuContent = menuContent
    }

    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(valueText)
                    .font(Typography.body)
                    .foregroundStyle(isPlaceholder ? colors.mutedForeground : colors.foreground)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: IconSize.xs, weight: .semibold))
                    .foregroundStyle(colors.mutedForeground)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(colors.input)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(colors.border, lineWidth: BorderWidth.default)
            )
        }
        .buttonStyle(.plain)
    }
}

struct BoardCheckboxRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isOn ? colors.primary : colors.input)
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .stroke(isOn ? colors.primary : colors.border, lineWidth: BorderWidth.default)
                    )
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(colors.primaryForeground)
                        }
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(colors.foreground)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isOn ? colors.accent : (isHovered ? colors.secondary.opacity(0.35) : colors.input.opacity(0.75)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(isOn ? colors.primary.opacity(0.28) : colors.border, lineWidth: BorderWidth.default)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }
}

struct BoardInlineMessage: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Tone {
        case error
        case info
    }

    let text: String
    let tone: Tone

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: tone == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: IconSize.sm, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(text)
                .font(Typography.caption)
                .foregroundStyle(iconColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var iconColor: Color {
        switch tone {
        case .error:
            return colors.destructive
        case .info:
            return colors.primary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .error:
            return colors.destructive.opacity(0.08)
        case .info:
            return colors.accent
        }
    }
}
