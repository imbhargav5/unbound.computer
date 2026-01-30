import ActivityKit
import SwiftUI

struct ClaudeActivityAttributes: ActivityAttributes {
    // Static data that doesn't change during the activity
    public struct ContentState: Codable, Hashable {
        // Dynamic data that can update
        var activeSessionCount: Int
        var sessions: [SessionInfo]

        struct SessionInfo: Codable, Hashable {
            let projectName: String
            let status: String // "generating", "reviewing", "ready", "prReady", "merged", "failed"
            let progress: Double
        }
    }

    // Static attributes
    var deviceName: String
}
