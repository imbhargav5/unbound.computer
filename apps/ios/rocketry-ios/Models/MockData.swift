import Foundation

enum MockData {
    // MARK: - Devices
    static let devices: [Device] = [
        Device(
            id: UUID(),
            name: "Bhargav's MacBook Pro",
            type: .macbookPro,
            hostname: "bhargavs-mbp.local",
            ipAddress: "192.168.1.100",
            status: .online,
            lastSeen: Date(),
            osVersion: "macOS 15.2",
            projectCount: 12
        ),
        Device(
            id: UUID(),
            name: "Office Mac Mini",
            type: .macMini,
            hostname: "office-mac.local",
            ipAddress: "192.168.1.101",
            status: .online,
            lastSeen: Date().addingTimeInterval(-300),
            osVersion: "macOS 15.1",
            projectCount: 5
        ),
        Device(
            id: UUID(),
            name: "Home iMac",
            type: .imac,
            hostname: "home-imac.local",
            ipAddress: "192.168.1.102",
            status: .offline,
            lastSeen: Date().addingTimeInterval(-86400),
            osVersion: "macOS 14.7",
            projectCount: 8
        ),
        Device(
            id: UUID(),
            name: "Dev Linux Server",
            type: .linux,
            hostname: "dev-server.local",
            ipAddress: "192.168.1.200",
            status: .busy,
            lastSeen: Date(),
            osVersion: "Ubuntu 24.04",
            projectCount: 15
        )
    ]

    // MARK: - Projects
    static let projects: [Project] = [
        Project(
            id: UUID(),
            name: "rocketry-ios",
            path: "~/Code/rocketry-ios",
            language: .swift,
            lastAccessed: Date(),
            chatCount: 3,
            description: "iOS app for Claude Code remote control",
            isFavorite: true
        ),
        Project(
            id: UUID(),
            name: "claude-code",
            path: "~/Code/claude-code",
            language: .typescript,
            lastAccessed: Date().addingTimeInterval(-3600),
            chatCount: 15,
            description: "Claude Code CLI tool",
            isFavorite: true
        ),
        Project(
            id: UUID(),
            name: "ml-pipeline",
            path: "~/Code/ml-pipeline",
            language: .python,
            lastAccessed: Date().addingTimeInterval(-7200),
            chatCount: 8,
            description: "Machine learning data pipeline",
            isFavorite: false
        ),
        Project(
            id: UUID(),
            name: "rust-server",
            path: "~/Code/rust-server",
            language: .rust,
            lastAccessed: Date().addingTimeInterval(-86400),
            chatCount: 2,
            description: "High-performance API server",
            isFavorite: false
        ),
        Project(
            id: UUID(),
            name: "web-dashboard",
            path: "~/Code/web-dashboard",
            language: .javascript,
            lastAccessed: Date().addingTimeInterval(-43200),
            chatCount: 6,
            description: "Admin dashboard frontend",
            isFavorite: false
        ),
        Project(
            id: UUID(),
            name: "go-microservices",
            path: "~/Code/go-microservices",
            language: .go,
            lastAccessed: Date().addingTimeInterval(-172800),
            chatCount: 4,
            description: "Microservices architecture",
            isFavorite: true
        )
    ]

    // MARK: - Chats
    static let chats: [Chat] = [
        Chat(
            id: UUID(),
            title: "Implement device list view",
            createdAt: Date().addingTimeInterval(-3600),
            lastMessageAt: Date(),
            messageCount: 24,
            preview: "The device list is now complete with proper styling and animations...",
            status: .active
        ),
        Chat(
            id: UUID(),
            title: "Fix navigation stack issues",
            createdAt: Date().addingTimeInterval(-7200),
            lastMessageAt: Date().addingTimeInterval(-1800),
            messageCount: 12,
            preview: "I've updated the navigation to use proper path-based routing...",
            status: .completed
        ),
        Chat(
            id: UUID(),
            title: "Add dark mode support",
            createdAt: Date().addingTimeInterval(-86400),
            lastMessageAt: Date().addingTimeInterval(-43200),
            messageCount: 8,
            preview: "Dark mode is now fully implemented with semantic colors...",
            status: .completed
        ),
        Chat(
            id: UUID(),
            title: "Refactor data models",
            createdAt: Date().addingTimeInterval(-172800),
            lastMessageAt: Date().addingTimeInterval(-86400),
            messageCount: 15,
            preview: "The models have been refactored to use Codable and Hashable...",
            status: .archived
        ),
        Chat(
            id: UUID(),
            title: "Setup project architecture",
            createdAt: Date().addingTimeInterval(-259200),
            lastMessageAt: Date().addingTimeInterval(-172800),
            messageCount: 32,
            preview: "The MVVM architecture is now in place with proper separation...",
            status: .completed
        )
    ]

    // MARK: - Messages
    static let messages: [Message] = [
        Message(
            id: UUID(),
            content: "Can you help me create a beautiful device list interface?",
            role: .user,
            timestamp: Date().addingTimeInterval(-600),
            codeBlocks: nil,
            isStreaming: false
        ),
        Message(
            id: UUID(),
            content: "I'll create a polished device list interface for you. The design will include device icons, status indicators, and smooth animations. Here's the implementation:",
            role: .assistant,
            timestamp: Date().addingTimeInterval(-540),
            codeBlocks: [
                Message.CodeBlock(
                    id: UUID(),
                    language: "swift",
                    code: """
                    struct DeviceRowView: View {
                        let device: Device

                        var body: some View {
                            HStack(spacing: 16) {
                                DeviceIcon(type: device.type)
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text(device.hostname)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusIndicator(status: device.status)
                            }
                            .padding()
                        }
                    }
                    """,
                    filename: "DeviceRowView.swift"
                )
            ],
            isStreaming: false
        ),
        Message(
            id: UUID(),
            content: "That looks great! Can you also add a search bar?",
            role: .user,
            timestamp: Date().addingTimeInterval(-300),
            codeBlocks: nil,
            isStreaming: false
        ),
        Message(
            id: UUID(),
            content: "Of course! I'll add a searchable modifier to the list view. This will automatically add a search bar that filters devices by name or hostname.",
            role: .assistant,
            timestamp: Date().addingTimeInterval(-240),
            codeBlocks: nil,
            isStreaming: false
        )
    ]

    // MARK: - Helper Functions
    static func projects(for device: Device) -> [Project] {
        // Return a subset of projects based on device project count
        Array(projects.prefix(min(device.projectCount, projects.count)))
    }

    static func chats(for project: Project) -> [Chat] {
        // Return a subset of chats based on project chat count
        Array(chats.prefix(min(project.chatCount, chats.count)))
    }
}
