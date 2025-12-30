import SwiftUI

struct SessionRowView: View {
    let session: ActiveSession
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Header: Project + Device
                HStack(spacing: 8) {
                    // Language icon
                    ZStack {
                        Circle()
                            .fill(session.language.color.opacity(0.2))
                            .frame(width: 32, height: 32)

                        Image(systemName: session.language.iconName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(session.language.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.projectName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(session.deviceName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    SessionStatusBadge(status: session.status, progress: session.progress)
                }

                // Chat title
                Text(session.chatTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Progress bar for generating
                if session.status == .generating {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)

                            // Progress
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppTheme.accentGradient)
                                .frame(width: geometry.size.width * session.progress, height: 4)
                                .animation(.linear(duration: 0.1), value: session.progress)

                            // Shimmer overlay
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            .white.opacity(0.3),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 40, height: 4)
                                .offset(x: shimmerOffset(width: geometry.size.width))
                        }
                    }
                    .frame(height: 4)
                }

                // Time elapsed
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(timeElapsed)
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPressed = false
                    }
                }
        )
    }

    private var timeElapsed: String {
        let elapsed = Date().timeIntervalSince(session.startedAt)
        if elapsed < 60 {
            return "\(Int(elapsed))s ago"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        } else {
            return "\(Int(elapsed / 3600))h ago"
        }
    }

    @State private var shimmerPhase: CGFloat = 0

    private func shimmerOffset(width: CGFloat) -> CGFloat {
        // Simple shimmer animation would go here
        // For now, return a static position
        return width * session.progress - 20
    }
}

#Preview {
    VStack(spacing: 12) {
        SessionRowView(
            session: ActiveSession(
                id: UUID(),
                projectName: "rocketry-ios",
                chatTitle: "Implement device list view",
                deviceName: "MacBook Pro",
                status: .generating,
                progress: 0.65,
                startedAt: Date().addingTimeInterval(-45),
                language: .swift
            )
        ) {}

        SessionRowView(
            session: ActiveSession(
                id: UUID(),
                projectName: "claude-code",
                chatTitle: "Fix navigation issues",
                deviceName: "MacBook Pro",
                status: .prReady,
                progress: 1.0,
                startedAt: Date().addingTimeInterval(-300),
                language: .typescript
            )
        ) {}
    }
    .padding()
}
