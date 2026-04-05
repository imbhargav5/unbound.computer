//
//  IconTooltip.swift
//  unbound-macos
//
//  Custom hover tooltip for icon-only controls.
//

import SwiftUI

enum IconTooltipPlacement: Equatable {
    case top
    case bottom

    var alignment: Alignment {
        switch self {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }

    var visibleOffset: CGFloat {
        switch self {
        case .top:
            return -(LayoutMetrics.toolbarIconHitSize + TooltipMetrics.gap)
        case .bottom:
            return LayoutMetrics.toolbarIconHitSize + TooltipMetrics.gap
        }
    }

    var hiddenOffset: CGFloat {
        switch self {
        case .top:
            return visibleOffset + TooltipMetrics.travel
        case .bottom:
            return visibleOffset - TooltipMetrics.travel
        }
    }
}

struct IconTooltipSpec: Equatable {
    let label: String
    let shortcut: String?
    let placement: IconTooltipPlacement

    init(
        _ label: String,
        shortcut: String? = nil,
        placement: IconTooltipPlacement = .top
    ) {
        self.label = label
        self.shortcut = shortcut
        self.placement = placement
    }

    var displayText: String {
        if let shortcut, !shortcut.isEmpty {
            return "\(label) \(shortcut)"
        }
        return label
    }

    var helpText: String {
        displayText
    }
}

private struct IconTooltipBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    let spec: IconTooltipSpec

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(spec.label)
                .font(GeistFont.sans(size: FontSize.xs, weight: .medium))
                .foregroundStyle(colors.tooltipForeground)

            if let shortcut = spec.shortcut, !shortcut.isEmpty {
                Text(shortcut)
                    .font(GeistFont.mono(size: FontSize.xs, weight: .medium))
                    .foregroundStyle(colors.tooltipForeground.opacity(0.72))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, TooltipMetrics.horizontalPadding)
        .padding(.vertical, TooltipMetrics.verticalPadding)
        .background(colors.tooltipBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(colors.tooltipBorder, lineWidth: BorderWidth.default)
        )
        .shadow(
            color: Color.black.opacity(Elevation.lg.opacity),
            radius: Elevation.lg.radius,
            y: Elevation.lg.y
        )
        .fixedSize()
    }
}

private struct IconTooltipModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let spec: IconTooltipSpec?

    @State private var isTooltipVisible = false
    @State private var showTask: Task<Void, Never>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let spec {
            content
                .help(spec.helpText)
                .overlay(alignment: spec.placement.alignment) {
                    IconTooltipBubble(spec: spec)
                        .opacity(isTooltipVisible ? 1 : 0)
                        .scaleEffect(reduceMotion ? 1 : (isTooltipVisible ? 1 : 0.96))
                        .offset(y: isTooltipVisible ? spec.placement.visibleOffset : spec.placement.hiddenOffset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(10)
                }
                .onHover { hovering in
                    handleHover(hovering)
                }
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { hideTooltip(animated: false) }
                )
                .onDisappear {
                    cancelPendingShow()
                    isTooltipVisible = false
                }
        } else {
            content
        }
    }

    private func handleHover(_ hovering: Bool) {
        cancelPendingShow()

        if hovering {
            showTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Duration.tooltipHoverDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(showAnimation) {
                    isTooltipVisible = true
                }
            }
        } else {
            hideTooltip(animated: true)
        }
    }

    private func hideTooltip(animated: Bool) {
        cancelPendingShow()
        guard isTooltipVisible else { return }

        if animated {
            withAnimation(hideAnimation) {
                isTooltipVisible = false
            }
        } else {
            isTooltipVisible = false
        }
    }

    private func cancelPendingShow() {
        showTask?.cancel()
        showTask = nil
    }

    private var showAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: Duration.fast)
            : .spring(response: Duration.medium, dampingFraction: 0.82)
    }

    private var hideAnimation: Animation {
        .easeOut(duration: Duration.fast)
    }
}

extension View {
    func iconTooltip(_ spec: IconTooltipSpec?) -> some View {
        modifier(IconTooltipModifier(spec: spec))
    }
}
