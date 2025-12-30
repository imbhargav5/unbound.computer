import Foundation

struct Chat: Identifiable, Hashable {
    let id: UUID
    let title: String
    let createdAt: Date
    let lastMessageAt: Date
    let messageCount: Int
    let preview: String
    let status: ChatStatus

    enum ChatStatus: String, Codable {
        case active
        case completed
        case archived

        var iconName: String {
            switch self {
            case .active:
                return "bubble.left.and.bubble.right"
            case .completed:
                return "checkmark.circle"
            case .archived:
                return "archivebox"
            }
        }
    }
}
