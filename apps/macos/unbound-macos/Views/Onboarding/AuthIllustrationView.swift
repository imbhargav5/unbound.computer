//
//  AuthIllustrationView.swift
//  unbound-macos
//
//  Right panel illustration for auth screens.
//  Shows architecture diagram: Phone → Lock → Machine
//  Plus terminal mockup and feature badges.
//

import SwiftUI

struct AuthIllustrationView: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.white.opacity(0.02), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Grid pattern (subtle)
            gridPattern
                .opacity(0.02)

            // Content
            VStack(spacing: Spacing.xxxxl) {
                Spacer()

                // Architecture diagram
                architectureDiagram

                // Terminal mockup
                terminalMockup

                // Feature badges
                featureBadges

                Spacer()
            }
            .padding(Spacing.xxxxl)
        }
        .background(Color.black)
    }

    // MARK: - Architecture Diagram

    private var architectureDiagram: some View {
        HStack(spacing: 0) {
            // Phone icon
            deviceIcon(systemName: "iphone", label: "iPhone")

            // Connecting line
            connectingLine

            // Lock icon (relay)
            VStack(spacing: Spacing.sm) {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "lock.shield")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.7))
                    )

                Text("E2E Encrypted")
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.3))
            }

            // Connecting line
            connectingLine

            // Mac icon
            deviceIcon(systemName: "desktopcomputer", label: "Mac")
        }
    }

    private func deviceIcon(systemName: String, label: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: systemName)
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.7))
                )

            Text(label)
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private var connectingLine: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 60, height: 1)
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.xl) // Align with icons
    }

    // MARK: - Terminal Mockup

    private var terminalMockup: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Window controls
            HStack(spacing: Spacing.sm) {
                Circle().fill(Color.white.opacity(0.2)).frame(width: 10, height: 10)
                Circle().fill(Color.white.opacity(0.2)).frame(width: 10, height: 10)
                Circle().fill(Color.white.opacity(0.2)).frame(width: 10, height: 10)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.white.opacity(0.02))

            // Terminal content
            VStack(alignment: .leading, spacing: Spacing.xs) {
                terminalLine("$ ", "claude", " --workspace my-project")
                terminalLine("", "Connecting to session...", "", color: .white.opacity(0.4))
                terminalLine("", "Session active", " (streaming from iPhone)", color: Color(hex: "22c55e").opacity(0.7))
                terminalLine("", "", "")
                terminalLine("> ", "Analyzing codebase...", "", color: .white.opacity(0.5))
            }
            .padding(Spacing.lg)
        }
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 400)
    }

    private func terminalLine(_ prefix: String, _ main: String, _ suffix: String, color: Color = .white.opacity(0.5)) -> some View {
        HStack(spacing: 0) {
            Text(prefix)
                .foregroundStyle(.white.opacity(0.3))
            Text(main)
                .foregroundStyle(color)
            Text(suffix)
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        }
        .font(Typography.terminal)
    }

    // MARK: - Feature Badges

    private var featureBadges: some View {
        HStack(spacing: Spacing.md) {
            featureBadge(icon: "lock.fill", text: "Zero Trust")
            featureBadge(icon: "shield.checkered", text: "E2E Encrypted")
            featureBadge(icon: "bolt.fill", text: "Real-time")
        }
    }

    private func featureBadge(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))

            Text(text)
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: Radius.full))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.full)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Grid Pattern

    private var gridPattern: some View {
        Canvas { context, size in
            let gridSize: CGFloat = 40
            let lineColor = Color.white

            for x in stride(from: 0, to: size.width, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }

            for y in stride(from: 0, to: size.height, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
        }
    }
}

#Preview {
    AuthIllustrationView()
        .frame(width: 600, height: 700)
}
