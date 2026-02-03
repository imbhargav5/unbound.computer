//
//  ComplicationViews.swift
//  mockup-watchos Watch App
//

import SwiftUI
import WidgetKit

// MARK: - Complication Entry

struct SessionComplicationEntry: TimelineEntry {
    let date: Date
    let sessionCount: Int
    let activeCount: Int
    let waitingCount: Int
    let hasError: Bool

    static var placeholder: SessionComplicationEntry {
        SessionComplicationEntry(
            date: Date(),
            sessionCount: 3,
            activeCount: 2,
            waitingCount: 1,
            hasError: false
        )
    }

    static var empty: SessionComplicationEntry {
        SessionComplicationEntry(
            date: Date(),
            sessionCount: 0,
            activeCount: 0,
            waitingCount: 0,
            hasError: false
        )
    }
}

// MARK: - Circular Complication

struct CircularComplicationView: View {
    let entry: SessionComplicationEntry

    var body: some View {
        ZStack {
            if entry.sessionCount == 0 {
                // Empty state
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            } else {
                // Session count with activity indicator
                VStack(spacing: 0) {
                    Text("\(entry.activeCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    if entry.waitingCount > 0 {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else if entry.activeCount > 0 {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Corner Complication

struct CornerComplicationView: View {
    let entry: SessionComplicationEntry

    var body: some View {
        ZStack {
            if entry.sessionCount == 0 {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    Text("\(entry.activeCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    if entry.waitingCount > 0 {
                        Circle()
                            .fill(.orange)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .widgetLabel {
            if entry.activeCount > 0 {
                Text("sessions")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Inline Complication

struct InlineComplicationView: View {
    let entry: SessionComplicationEntry

    var body: some View {
        if entry.sessionCount == 0 {
            Label("No sessions", systemImage: "sparkles")
        } else if entry.waitingCount > 0 {
            Label("\(entry.waitingCount) waiting", systemImage: "questionmark.circle.fill")
        } else {
            Label("\(entry.activeCount) active", systemImage: "sparkles")
        }
    }
}

// MARK: - Rectangular Complication

struct RectangularComplicationView: View {
    let entry: SessionComplicationEntry

    var body: some View {
        HStack(spacing: WatchTheme.spacingM) {
            // Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(statusColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                if entry.sessionCount == 0 {
                    Text("No Sessions")
                        .font(.system(size: 13, weight: .medium))
                    Text("All quiet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(entry.activeCount) Active")
                        .font(.system(size: 13, weight: .medium))

                    if entry.waitingCount > 0 {
                        Text("\(entry.waitingCount) need input")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    } else {
                        Text("Running")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var statusColor: Color {
        if entry.hasError {
            return .red
        } else if entry.waitingCount > 0 {
            return .orange
        } else if entry.activeCount > 0 {
            return .green
        } else {
            return .secondary
        }
    }

    private var statusIcon: String {
        if entry.hasError {
            return "exclamationmark.triangle.fill"
        } else if entry.waitingCount > 0 {
            return "questionmark.circle.fill"
        } else if entry.activeCount > 0 {
            return "sparkles"
        } else {
            return "sparkles"
        }
    }
}

// MARK: - Previews

#Preview("Circular - Active") {
    CircularComplicationView(
        entry: SessionComplicationEntry(
            date: Date(),
            sessionCount: 3,
            activeCount: 2,
            waitingCount: 0,
            hasError: false
        )
    )
    .frame(width: 50, height: 50)
}

#Preview("Circular - Waiting") {
    CircularComplicationView(
        entry: SessionComplicationEntry(
            date: Date(),
            sessionCount: 2,
            activeCount: 1,
            waitingCount: 1,
            hasError: false
        )
    )
    .frame(width: 50, height: 50)
}

#Preview("Circular - Empty") {
    CircularComplicationView(
        entry: .empty
    )
    .frame(width: 50, height: 50)
}

#Preview("Rectangular") {
    RectangularComplicationView(
        entry: SessionComplicationEntry(
            date: Date(),
            sessionCount: 3,
            activeCount: 2,
            waitingCount: 1,
            hasError: false
        )
    )
    .frame(width: 150, height: 50)
}

#Preview("Rectangular - Empty") {
    RectangularComplicationView(
        entry: .empty
    )
    .frame(width: 150, height: 50)
}
