//
//  SessionRowView.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct SessionRowView: View {
    let session: WatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTheme.spacingS) {
            // Top row: status indicator and project name
            HStack(spacing: WatchTheme.spacingS) {
                Circle()
                    .fill(session.status.color)
                    .frame(width: 8, height: 8)

                Text(session.projectName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Spacer()
            }

            // Bottom row: device name and elapsed time
            HStack {
                Image(systemName: session.deviceType.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(session.deviceName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if session.status.isActive {
                    Text(session.elapsedTimeFormatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Status or MCQ indicator
            if session.status == .waitingInput, session.pendingMCQ != nil {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Needs response")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.orange)
            } else {
                StatusBadge(status: session.status, compact: true)
            }
        }
        .padding(.vertical, WatchTheme.spacingS)
    }
}

#Preview("Session Row") {
    List {
        ForEach(WatchMockData.sessions) { session in
            SessionRowView(session: session)
        }
    }
}
