import ActivityKit
import Logging
import CryptoKit
import SwiftUI

private let logger = Logger(label: "app.ui")

@Observable
class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<ClaudeActivityAttributes>?

    /// The push token for the current Live Activity (for APNs updates)
    private(set) var activityPushToken: String?

    var isActivityActive: Bool {
        currentActivity != nil
    }

    /// Whether Live Activities are supported on this device
    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private init() {
        // Resume any existing activity on init
        resumeExistingActivity()
    }

    func startLiveActivity(sessions: [ActiveSession]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities are not enabled")
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
                pushType: .token  // Enable push updates
            )
            currentActivity = activity
            logger.info("Started Live Activity: \(activity.id)")

            // Monitor push token updates
            Task {
                await monitorPushTokenUpdates(for: activity)
            }
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
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
                activityPushToken = nil
            }
        }
    }

    // MARK: - Push Token Management

    /// Monitor push token updates for a Live Activity
    private func monitorPushTokenUpdates(for activity: Activity<ClaudeActivityAttributes>) async {
        for await tokenData in activity.pushTokenUpdates {
            let tokenString = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
            await MainActor.run {
                self.activityPushToken = tokenString
            }
            logger.debug("Live Activity push token fingerprint: \(redactedFingerprint(tokenString))")

            // Register the token with the backend
            await registerActivityPushToken(tokenString, activityId: activity.id)
        }
    }

    /// Register the Live Activity push token with the backend
    private func registerActivityPushToken(_ token: String, activityId: String) async {
        guard let deviceId = DeviceTrustService.shared.deviceId else {
            logger.warning("Cannot register activity push token: no device ID")
            return
        }

        do {
            let accessToken = try await AuthService.shared.getAccessToken()

            var request = URLRequest(url: Config.apiURL.appendingPathComponent("/api/v1/mobile/live-activity/token"))
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let body: [String: Any] = [
                "deviceId": deviceId.uuidString,
                "activityId": activityId,
                "pushToken": token,
                "apnsEnvironment": PushNotificationService.shared.apnsEnvironment
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.warning("Invalid response from activity token registration")
                return
            }

            if httpResponse.statusCode == 200 {
                logger.info("Live Activity push token registered successfully")
            } else {
                logger.error(
                    "Failed to register activity push token: \(httpResponse.statusCode), response_summary=\(redactedResponseSummary(data))"
                )
            }
        } catch {
            logger.error("Error registering activity push token: \(error)")
        }
    }

    // MARK: - Activity Resume

    /// Resume any existing activity on app launch
    private func resumeExistingActivity() {
        for activity in Activity<ClaudeActivityAttributes>.activities {
            self.currentActivity = activity

            // Re-monitor push token updates
            Task {
                await monitorPushTokenUpdates(for: activity)
            }

            logger.info("Resumed existing Live Activity: \(activity.id)")
            break  // Only track one activity
        }
    }

    private func redactedFingerprint(_ rawValue: String) -> String {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    private func redactedResponseSummary(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "bytes=\(data.count),sha256:\(hex)"
    }
}
