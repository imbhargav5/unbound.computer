//
//  CommonModifiers.swift
//  unbound-macos
//
//  Common shadcn-style modifiers
//

import SwiftUI
import AppKit

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
            .background(isHovering ? colors.hoverBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
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
            .background(isSelected ? colors.selectionBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
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
                .fill(colors.panelDivider)
                .frame(height: BorderWidth.default)
        case .vertical:
            Rectangle()
                .fill(colors.panelDivider)
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
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
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

    func borderStyle(radius: CGFloat = Radius.sm, width: CGFloat = BorderWidth.default) -> some View {
        modifier(BorderStyleModifier(radius: radius, width: width))
    }

    func hoverEffect() -> some View {
        modifier(HoverEffectModifier())
    }

    func fullRowHitTarget(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
    }

    func selectionStyle(isSelected: Bool) -> some View {
        modifier(SelectionModifier(isSelected: isSelected))
    }

    // MARK: - Animation Modifiers

    /// Slide in from a direction with fade
    func slideIn(isVisible: Bool, from edge: Edge = .bottom, delay: Double = 0) -> some View {
        modifier(SlideInModifier(isVisible: isVisible, edge: edge, delay: delay))
    }

    /// Scale and fade in/out
    func scaleFade(isVisible: Bool, initialScale: CGFloat = 0.9, delay: Double = 0) -> some View {
        modifier(ScaleFadeModifier(isVisible: isVisible, initialScale: initialScale, delay: delay))
    }

    /// Pulse animation for loading states
    func pulse(when isActive: Bool) -> some View {
        modifier(PulseModifier(isActive: isActive))
    }

    /// Apply elevation shadow
    func elevation(_ level: ElevationValue) -> some View {
        modifier(ElevationModifier(elevation: level))
    }

    // MARK: - Vibrancy Modifiers

    /// Apply sidebar vibrancy background (macOS native blur)
    func sidebarVibrancy() -> some View {
        background(VibrancyView(material: .sidebar))
    }

    /// Apply popover vibrancy background (macOS native blur)
    func popoverVibrancy() -> some View {
        background(VibrancyView(material: .popover))
    }

    /// Apply menu vibrancy background (macOS native blur)
    func menuVibrancy() -> some View {
        background(VibrancyView(material: .menu))
    }
}

// MARK: - Slide In Modifier

struct SlideInModifier: ViewModifier {
    let isVisible: Bool
    let edge: Edge
    let delay: Double

    private var offset: CGSize {
        switch edge {
        case .top:
            return CGSize(width: 0, height: -20)
        case .bottom:
            return CGSize(width: 0, height: 20)
        case .leading:
            return CGSize(width: -20, height: 0)
        case .trailing:
            return CGSize(width: 20, height: 0)
        }
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(isVisible ? .zero : offset)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.8)
                    .delay(delay),
                value: isVisible
            )
    }
}

// MARK: - Scale Fade Modifier

struct ScaleFadeModifier: ViewModifier {
    let isVisible: Bool
    let initialScale: CGFloat
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : initialScale)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.7)
                    .delay(delay),
                value: isVisible
            )
    }
}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    let isActive: Bool
    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .opacity(animating && isActive ? 0.5 : 1)
            .animation(
                isActive
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: animating
            )
            .onAppear {
                animating = true
            }
            .onChange(of: isActive) { _, newValue in
                if !newValue {
                    animating = false
                }
            }
    }
}

// MARK: - Elevation Modifier

struct ElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let elevation: ElevationValue

    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color(hex: "0D0D0D").opacity(colorScheme == .dark ? elevation.opacity * 1.5 : elevation.opacity),
                radius: elevation.radius,
                x: 0,
                y: elevation.y
            )
    }
}

// MARK: - Vibrancy View (NSVisualEffectView wrapper)

struct VibrancyView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - Typing Dots Indicator

struct TypingDotsIndicator: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animatingDot = 0

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    let dotCount = 3
    let dotSize: CGFloat = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(colors.mutedForeground)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: animatingDot == index ? -3 : 0)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                animatingDot = (animatingDot + 1) % dotCount
            }
        }
    }
}

// MARK: - Window Toolbar (Custom Title Bar)

/// A custom toolbar that works with macOS transparent titlebar.
/// The titlebar still exists (~28pt) with traffic lights, but is transparent.
///
/// Requirements for this to work:
/// - Window must have `.fullSizeContentView` in styleMask
/// - Window must have `titlebarAppearsTransparent = true`
/// - Window must have `titleVisibility = .hidden`
struct WindowToolbar<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(WindowDragView())
    }
}

/// NSView that enables window dragging and double-click to zoom
struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Custom NSView that handles window dragging and double-click zoom
class WindowDragNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isMovableByWindowBackground = true
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        }
        super.mouseUp(with: event)
    }
}

/// A draggable spacer that fills available space in the toolbar
struct ToolbarDraggableSpacer: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Makes this view a window drag area (for custom toolbars)
    func windowDraggable() -> some View {
        background(WindowDragView())
    }
}

// MARK: - Window Titlebar Configuration

/// Configures the NSWindow to allow custom titlebar content.
struct WindowTitlebarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView)
    }

    private func configureWindow(for view: NSView?) {
        guard let window = view?.window else { return }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
    }
}
