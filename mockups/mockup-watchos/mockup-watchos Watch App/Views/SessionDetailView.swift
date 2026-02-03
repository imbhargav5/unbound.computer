//
//  SessionDetailView.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct SessionDetailView: View {
    @Binding var session: WatchSession
    @State private var showMCQ = false
    @State private var showStopConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: WatchTheme.spacingL) {
                // Header
                sessionHeader

                // Status indicator
                statusSection

                // Actions
                actionButtons

                // MCQ prompt if available
                if session.pendingMCQ != nil {
                    mcqPrompt
                }
            }
            .padding(.horizontal, WatchTheme.spacingS)
        }
        .navigationTitle(session.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMCQ) {
            if let mcq = session.pendingMCQ {
                MCQReplyView(mcq: mcq) { answer in
                    handleMCQAnswer(answer)
                }
            }
        }
        .confirmationDialog(
            "Stop Session?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) {
                stopSession()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var sessionHeader: some View {
        VStack(spacing: WatchTheme.spacingS) {
            // Device info
            HStack(spacing: WatchTheme.spacingS) {
                Image(systemName: session.deviceType.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(session.deviceName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Elapsed time
            if session.status.isActive {
                Text(session.elapsedTimeFormatted)
                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var statusSection: some View {
        VStack(spacing: WatchTheme.spacingM) {
            // Large status icon
            ZStack {
                Circle()
                    .fill(session.status.color.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: session.status.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(session.status.color)
                    .symbolEffect(.pulse, isActive: session.status == .generating)
            }

            // Status label
            Text(session.status.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(session.status.color)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: WatchTheme.spacingM) {
            // Pause/Resume button
            if session.status.canPause {
                Button {
                    pauseSession()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 16))
                        Text("Pause")
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchTheme.spacingM)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
            } else if session.status.canResume {
                Button {
                    resumeSession()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                        Text("Resume")
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchTheme.spacingM)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }

            // Stop button
            if session.status.canStop {
                Button {
                    showStopConfirmation = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16))
                        Text("Stop")
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchTheme.spacingM)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    private var mcqPrompt: some View {
        Button {
            showMCQ = true
            HapticManager.mcqReceived()
        } label: {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Question")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Tap to respond")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(WatchTheme.spacingM)
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: WatchTheme.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func pauseSession() {
        HapticManager.buttonTap()
        session.status = .paused
        HapticManager.sessionStatusChanged(.paused)
    }

    private func resumeSession() {
        HapticManager.buttonTap()
        session.status = .generating
        HapticManager.sessionStatusChanged(.generating)
    }

    private func stopSession() {
        HapticManager.buttonTap()
        session.status = .completed
        HapticManager.sessionStatusChanged(.completed)
    }

    private func handleMCQAnswer(_ answer: String) {
        session.pendingMCQ = nil
        session.status = .generating
        HapticManager.mcqAnswered()
    }
}

#Preview("Session Detail - Generating") {
    NavigationStack {
        SessionDetailView(
            session: .constant(WatchMockData.sessions[0])
        )
    }
}

#Preview("Session Detail - Waiting Input") {
    NavigationStack {
        SessionDetailView(
            session: .constant(WatchMockData.sessions[1])
        )
    }
}

#Preview("Session Detail - Paused") {
    NavigationStack {
        SessionDetailView(
            session: .constant(WatchMockData.sessions[2])
        )
    }
}
