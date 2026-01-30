//
//  WorkspaceIcon.swift
//  unbound-macos
//
//  A fluid, morphing workspace icon inspired by Lucide's layout-grid.
//  Morphs into a rotating loader when the session is active/streaming.
//

import Foundation
import SwiftUI

// MARK: - Workspace Icon

/// A fluid workspace icon that morphs between a grid layout (rest) and a spinning loader (active)
struct WorkspaceIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let isActive: Bool
    let size: CGFloat

    @State private var rotation: Double = 0

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(isActive: Bool = false, size: CGFloat = 16) {
        self.isActive = isActive
        self.size = size
    }

    var body: some View {
        ZStack {
            if isActive {
                LoaderShape()
                    .stroke(colors.mutedForeground, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        startRotation()
                    }
            } else {
                GridShape()
                    .fill(colors.mutedForeground)
                    .frame(width: size, height: size)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
    }

    private var strokeWidth: CGFloat {
        size / 12
    }

    private func startRotation() {
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

// MARK: - Grid Shape (Lucide layout-grid inspired)

/// A 2x2 grid of rounded rectangles - represents workspace at rest
struct GridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let gap = rect.width * 0.1
        let cornerRadius = rect.width * 0.08
        let cellSize = (rect.width - gap) / 2

        // Top-left cell
        let topLeft = CGRect(x: 0, y: 0, width: cellSize, height: cellSize)
        path.addRoundedRect(in: topLeft, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // Top-right cell
        let topRight = CGRect(x: cellSize + gap, y: 0, width: cellSize, height: cellSize)
        path.addRoundedRect(in: topRight, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // Bottom-left cell
        let bottomLeft = CGRect(x: 0, y: cellSize + gap, width: cellSize, height: cellSize)
        path.addRoundedRect(in: bottomLeft, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // Bottom-right cell
        let bottomRight = CGRect(x: cellSize + gap, y: cellSize + gap, width: cellSize, height: cellSize)
        path.addRoundedRect(in: bottomRight, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        return path
    }
}

// MARK: - Loader Shape (Lucide loader inspired)

/// A radial loader with 8 lines emanating from center
struct LoaderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let innerRadius = rect.width * 0.2
        let outerRadius = rect.width * 0.45

        // 8 lines at 45-degree intervals
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4
            let start = CGPoint(
                x: center.x + innerRadius * Darwin.cos(angle),
                y: center.y + innerRadius * Darwin.sin(angle)
            )
            let end = CGPoint(
                x: center.x + outerRadius * Darwin.cos(angle),
                y: center.y + outerRadius * Darwin.sin(angle)
            )

            path.move(to: start)
            path.addLine(to: end)
        }

        return path
    }
}

// MARK: - Morphing Workspace Icon (Advanced)

/// An advanced morphing icon that smoothly transitions between grid and loader states
struct MorphingWorkspaceIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let isActive: Bool
    let size: CGFloat

    @State private var morphProgress: CGFloat = 0
    @State private var rotation: Double = 0

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(isActive: Bool = false, size: CGFloat = 16) {
        self.isActive = isActive
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            drawMorphedIcon(context: context, rect: rect)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(isActive ? rotation : 0))
        .onChange(of: isActive) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                morphProgress = newValue ? 1.0 : 0.0
            }
            if newValue {
                startRotation()
            } else {
                rotation = 0
            }
        }
        .onAppear {
            morphProgress = isActive ? 1.0 : 0.0
            if isActive {
                startRotation()
            }
        }
    }

    private func drawMorphedIcon(context: GraphicsContext, rect: CGRect) {
        let color = colors.mutedForeground

        // Interpolate between grid cells and loader lines
        let gap = rect.width * 0.1
        let cornerRadius = rect.width * 0.08 * (1 - morphProgress)
        let cellSize = (rect.width - gap) / 2

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let innerRadius = rect.width * 0.2
        let outerRadius = rect.width * 0.45

        // Draw 4 morphing elements
        for i in 0..<4 {
            let gridRect = gridCellRect(index: i, cellSize: cellSize, gap: gap)
            let lineAngle = Double(i * 2) * .pi / 4 // 0, 90, 180, 270 degrees

            // Calculate morphed positions
            let morphedPath = Path { path in
                if morphProgress < 0.5 {
                    // Morphing from grid to intermediate state
                    let localProgress = morphProgress * 2
                    let shrinkFactor = 1 - localProgress * 0.7

                    let shrunkRect = CGRect(
                        x: gridRect.minX + gridRect.width * (1 - shrinkFactor) / 2,
                        y: gridRect.minY + gridRect.height * (1 - shrinkFactor) / 2,
                        width: gridRect.width * shrinkFactor,
                        height: gridRect.height * shrinkFactor
                    )
                    path.addRoundedRect(in: shrunkRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
                } else {
                    // Morphing from intermediate to line
                    let localProgress = (morphProgress - 0.5) * 2

                    let start = CGPoint(
                        x: center.x + innerRadius * cos(lineAngle),
                        y: center.y + innerRadius * sin(lineAngle)
                    )
                    let end = CGPoint(
                        x: center.x + outerRadius * cos(lineAngle),
                        y: center.y + outerRadius * sin(lineAngle)
                    )

                    // Draw as a rounded line (capsule)
                    let lineWidth = rect.width * 0.12 * (1 - localProgress * 0.5)
                    path.move(to: start)
                    path.addLine(to: end)
                }
            }

            if morphProgress >= 0.5 {
                context.stroke(
                    morphedPath,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: rect.width / 12, lineCap: .round)
                )
            } else {
                context.fill(morphedPath, with: .color(color))
            }
        }

        // Draw additional 4 lines for loader (fade in during morph)
        if morphProgress > 0.3 {
            let lineOpacity = min(1.0, (morphProgress - 0.3) / 0.7)
            for i in 0..<4 {
                let lineAngle = Double(i * 2 + 1) * .pi / 4 // 45, 135, 225, 315 degrees

                let start = CGPoint(
                    x: center.x + innerRadius * Darwin.cos(lineAngle),
                    y: center.y + innerRadius * Darwin.sin(lineAngle)
                )
                let end = CGPoint(
                    x: center.x + outerRadius * Darwin.cos(lineAngle),
                    y: center.y + outerRadius * Darwin.sin(lineAngle)
                )

                var linePath = Path()
                linePath.move(to: start)
                linePath.addLine(to: end)

                context.stroke(
                    linePath,
                    with: .color(color.opacity(lineOpacity)),
                    style: StrokeStyle(lineWidth: rect.width / 12, lineCap: .round)
                )
            }
        }
    }

    private func gridCellRect(index: Int, cellSize: CGFloat, gap: CGFloat) -> CGRect {
        switch index {
        case 0: return CGRect(x: 0, y: 0, width: cellSize, height: cellSize)
        case 1: return CGRect(x: cellSize + gap, y: 0, width: cellSize, height: cellSize)
        case 2: return CGRect(x: cellSize + gap, y: cellSize + gap, width: cellSize, height: cellSize)
        case 3: return CGRect(x: 0, y: cellSize + gap, width: cellSize, height: cellSize)
        default: return .zero
        }
    }

    private func startRotation() {
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

// MARK: - Session Icon (Convenience Wrapper)

/// Convenience wrapper that uses the simpler WorkspaceIcon by default
/// Set `useMorphing: true` for the advanced morphing animation
struct SessionIcon: View {
    let isActive: Bool
    let size: CGFloat
    let useMorphing: Bool

    init(isActive: Bool = false, size: CGFloat = 14, useMorphing: Bool = false) {
        self.isActive = isActive
        self.size = size
        self.useMorphing = useMorphing
    }

    var body: some View {
        if useMorphing {
            MorphingWorkspaceIcon(isActive: isActive, size: size)
        } else {
            WorkspaceIcon(isActive: isActive, size: size)
        }
    }
}

// MARK: - Preview

#Preview("Workspace Icons") {
    VStack(spacing: 32) {
        Text("Simple Workspace Icon")
            .font(.headline)

        HStack(spacing: 24) {
            VStack {
                WorkspaceIcon(isActive: false, size: 24)
                Text("Rest")
                    .font(.caption)
            }

            VStack {
                WorkspaceIcon(isActive: true, size: 24)
                Text("Active")
                    .font(.caption)
            }
        }

        Divider()

        Text("Morphing Workspace Icon")
            .font(.headline)

        HStack(spacing: 24) {
            VStack {
                MorphingWorkspaceIcon(isActive: false, size: 24)
                Text("Rest")
                    .font(.caption)
            }

            VStack {
                MorphingWorkspaceIcon(isActive: true, size: 24)
                Text("Active")
                    .font(.caption)
            }
        }

        Divider()

        Text("Different Sizes")
            .font(.headline)

        HStack(spacing: 24) {
            WorkspaceIcon(isActive: false, size: 12)
            WorkspaceIcon(isActive: false, size: 16)
            WorkspaceIcon(isActive: false, size: 24)
            WorkspaceIcon(isActive: false, size: 32)
        }
    }
    .padding(32)
    .frame(width: 400, height: 500)
}

#Preview("Interactive Toggle") {
    struct InteractivePreview: View {
        @State private var isActive = false

        var body: some View {
            VStack(spacing: 24) {
                Text("Click to toggle state")
                    .font(.headline)

                HStack(spacing: 32) {
                    VStack {
                        WorkspaceIcon(isActive: isActive, size: 32)
                        Text("Simple")
                            .font(.caption)
                    }

                    VStack {
                        MorphingWorkspaceIcon(isActive: isActive, size: 32)
                        Text("Morphing")
                            .font(.caption)
                    }
                }

                Button(isActive ? "Stop" : "Start") {
                    isActive.toggle()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
        }
    }

    return InteractivePreview()
        .frame(width: 300, height: 250)
}
