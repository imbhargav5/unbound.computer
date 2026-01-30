import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct SessionDetailView: View {
    let sessionId: UUID

    // Using @State with @Observable (iOS 17+) instead of @StateObject with ObservableObject
    @State private var viewModel: SessionDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(sessionId: UUID) {
        self.sessionId = sessionId
        _viewModel = State(initialValue: SessionDetailViewModel(sessionId: sessionId))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let session = viewModel.session {
                        sessionHeaderView(session)
                            .padding(.horizontal)
                    }

                    if viewModel.isLoadingCold {
                        loadingView
                    } else if viewModel.events.isEmpty {
                        emptyEventsView
                    } else {
                        eventsListView
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(viewModel.session?.title ?? "Session")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    connectionIndicator
                }
                #else
                ToolbarItem(placement: .automatic) {
                    connectionIndicator
                }
                #endif
            }
            .task {
                // Phase 1: Cold load
                await viewModel.loadSessionCold()

                // Phase 2: Hot subscribe
                await viewModel.subscribeHot()
            }
            .onDisappear {
                Task {
                    await viewModel.unsubscribe()
                    viewModel.cleanup()
                }
            }
            .onChange(of: viewModel.events.count) { _, _ in
                // Auto-scroll to latest event
                if let lastEvent = viewModel.events.last {
                    withAnimation {
                        proxy.scrollTo(lastEvent.eventId, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func sessionHeaderView(_ session: CodingSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title ?? "Untitled Session")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                StatusBadge(status: session.status)
            }

            if let deviceName = session.executorDeviceName {
                Label(deviceName, systemImage: "laptopcomputer")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            if let projectPath = session.projectPath {
                Label(projectPath, systemImage: "folder")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Divider()

            // Statistics
            HStack(spacing: 20) {
                statItem(label: "Events", value: viewModel.events.count, icon: "bubble.left")

                if let toolCallCount = session.toolCallCount {
                    statItem(label: "Tools", value: toolCallCount, icon: "hammer")
                }

                if let errorCount = session.errorCount, errorCount > 0 {
                    statItem(label: "Errors", value: errorCount, icon: "exclamationmark.triangle", color: .red)
                }
            }
        }
        .padding()
        #if canImport(UIKit)
        .background(Color(uiColor: .systemGroupedBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .cornerRadius(12)
    }

    private func statItem(label: String, value: Int, icon: String, color: Color = .secondary) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            Text("\(value)")
                .font(.headline)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var eventsListView: some View {
        ForEach(viewModel.events) { event in
            EventRowView(event: event)
                .id(event.eventId)
                .padding(.horizontal)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading events...")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var emptyEventsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No events yet")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)

            Text(connectionText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected, .failed:
            return .red
        }
    }

    private var connectionText: String {
        switch viewModel.connectionState {
        case .connected:
            return "Live"
        case .connecting:
            return "Connecting..."
        case .reconnecting(let attempt):
            return "Reconnecting (\(attempt))"
        case .disconnected:
            return "Disconnected"
        case .failed:
            return "Failed"
        }
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(sessionId: UUID())
    }
}
