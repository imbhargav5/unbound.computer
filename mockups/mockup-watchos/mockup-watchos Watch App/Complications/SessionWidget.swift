//
//  SessionWidget.swift
//  mockup-watchos Watch App
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct SessionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionComplicationEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionComplicationEntry) -> Void) {
        // Return mock data for snapshot
        let entry = SessionComplicationEntry(
            date: Date(),
            sessionCount: WatchMockData.sessions.count,
            activeCount: WatchMockData.activeSessions.count,
            waitingCount: WatchMockData.waitingInputCount,
            hasError: WatchMockData.sessions.contains { $0.status == .error }
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionComplicationEntry>) -> Void) {
        // In production, this would fetch from WatchConnectivity or direct relay
        let entry = SessionComplicationEntry(
            date: Date(),
            sessionCount: WatchMockData.sessions.count,
            activeCount: WatchMockData.activeSessions.count,
            waitingCount: WatchMockData.waitingInputCount,
            hasError: WatchMockData.sessions.contains { $0.status == .error }
        )

        // Refresh every minute for active sessions
        let refreshDate = Date().addingTimeInterval(60)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

// MARK: - Widget Configuration

struct SessionWidget: Widget {
    let kind = "com.unbound.watchos.session-widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SessionTimelineProvider()) { entry in
            SessionWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Sessions")
        .description("Monitor your active Claude Code sessions")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

// MARK: - Widget Entry View

struct SessionWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SessionComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView(entry: entry)
        case .accessoryCorner:
            CornerComplicationView(entry: entry)
        case .accessoryInline:
            InlineComplicationView(entry: entry)
        case .accessoryRectangular:
            RectangularComplicationView(entry: entry)
        default:
            CircularComplicationView(entry: entry)
        }
    }
}

// MARK: - Widget Bundle (if adding multiple widgets)

// @main
// struct UnboundWidgets: WidgetBundle {
//     var body: some Widget {
//         SessionWidget()
//     }
// }
