import Foundation

struct CodingSession: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    let title: String?
    let status: SessionStatus
    let createdAt: Date
    let updatedAt: Date
    let lastActivityAt: Date?

    // Metadata
    let executorDeviceId: UUID?
    let executorDeviceName: String?
    let projectPath: String?

    // Statistics
    let eventCount: Int?
    let toolCallCount: Int?
    let errorCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastActivityAt = "last_activity_at"
        case executorDeviceId = "executor_device_id"
        case executorDeviceName = "executor_device_name"
        case projectPath = "project_path"
        case eventCount = "event_count"
        case toolCallCount = "tool_call_count"
        case errorCount = "error_count"
    }
}

enum SessionStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case cancelled
    case error

    var displayName: String {
        rawValue.capitalized
    }

    var systemIcon: String {
        switch self {
        case .active: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
