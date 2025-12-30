import ActivityKit
import SwiftUI

@Observable
class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<ClaudeActivityAttributes>?

    var isActivityActive: Bool {
        currentActivity != nil
    }

    private init() {}

    func startLiveActivity(sessions: [ActiveSession]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }

        // End any existing activity
        endLiveActivity()

        let attributes = ClaudeActivityAttributes(deviceName: "MacBook Pro")

        let contentState = ClaudeActivityAttributes.ContentState(
            activeSessionCount: sessions.count,
            sessions: sessions.map { session in
                ClaudeActivityAttributes.ContentState.SessionInfo(
                    projectName: session.projectName,
                    status: session.status.rawValue,
                    progress: session.progress
                )
            }
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            print("Started Live Activity: \(activity.id)")
        } catch {
            print("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func updateLiveActivity(sessions: [ActiveSession]) {
        guard let activity = currentActivity else { return }

        let contentState = ClaudeActivityAttributes.ContentState(
            activeSessionCount: sessions.count,
            sessions: sessions.map { session in
                ClaudeActivityAttributes.ContentState.SessionInfo(
                    projectName: session.projectName,
                    status: session.status.rawValue,
                    progress: session.progress
                )
            }
        )

        Task {
            await activity.update(
                ActivityContent(state: contentState, staleDate: nil)
            )
        }
    }

    func endLiveActivity() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run {
                currentActivity = nil
            }
        }
    }
}
