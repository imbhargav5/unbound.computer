import ActivityKit
import WidgetKit
import SwiftUI

struct RocketryWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClaudeActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenView(context: context)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text("Claude")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.activeSessionCount) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.center) {
                    // Nothing in center
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ForEach(context.state.sessions.prefix(3), id: \.projectName) { session in
                            SessionRowLiveActivity(session: session)
                        }
                    }
                    .padding(.horizontal, 4)
                }

            } compactLeading: {
                // Compact leading - icon
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                // Compact trailing - count
                Text("\(context.state.activeSessionCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)

            } minimal: {
                // Minimal - just icon
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<ClaudeActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Claude icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Code")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("\(context.state.activeSessionCount) sessions active")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            if let firstSession = context.state.sessions.first {
                StatusBadgeLiveActivity(status: firstSession.status, progress: firstSession.progress)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Session Row

struct SessionRowLiveActivity: View {
    let session: ClaudeActivityAttributes.ContentState.SessionInfo

    var body: some View {
        HStack(spacing: 8) {
            Text(session.projectName)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            StatusBadgeLiveActivity(status: session.status, progress: session.progress)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadgeLiveActivity: View {
    let status: String
    let progress: Double

    var statusIcon: String {
        switch status {
        case "generating": return "wand.and.stars"
        case "reviewing": return "eye"
        case "ready": return "checkmark.circle"
        case "prReady": return "arrow.triangle.pull"
        case "merged": return "arrow.triangle.merge"
        case "failed": return "exclamationmark.triangle"
        default: return "circle"
        }
    }

    var statusColor: Color {
        switch status {
        case "generating": return .orange
        case "reviewing": return .blue
        case "ready", "merged": return .green
        case "prReady": return .purple
        case "failed": return .red
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2)

            if status == "generating" {
                Text("\(Int(progress * 100))%")
                    .font(.caption2.bold())
            }
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.2))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: ClaudeActivityAttributes(deviceName: "MacBook Pro")) {
    RocketryWidgetLiveActivity()
} contentStates: {
    ClaudeActivityAttributes.ContentState(
        activeSessionCount: 3,
        sessions: [
            .init(projectName: "rocketry-ios", status: "generating", progress: 0.65),
            .init(projectName: "claude-code", status: "prReady", progress: 1.0),
            .init(projectName: "ml-pipeline", status: "merged", progress: 1.0)
        ]
    )
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: ClaudeActivityAttributes(deviceName: "MacBook Pro")) {
    RocketryWidgetLiveActivity()
} contentStates: {
    ClaudeActivityAttributes.ContentState(
        activeSessionCount: 3,
        sessions: [
            .init(projectName: "rocketry-ios", status: "generating", progress: 0.65),
            .init(projectName: "claude-code", status: "prReady", progress: 1.0),
            .init(projectName: "ml-pipeline", status: "merged", progress: 1.0)
        ]
    )
}
