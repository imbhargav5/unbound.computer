//
//  PreviewData.swift
//  unbound-ios
//
//  Rich fake data for Xcode Canvas previews.
//  Provides realistic data sets for all model types so that
//  #Preview blocks render with populated, meaningful UI.
//
//  Follows the same pattern as the macOS app: stable IDs,
//  realistic data, and centralized mock data.
//

#if DEBUG

import Foundation

// MARK: - Preview Data

enum PreviewData {

    // MARK: - Stable Identifiers (for cross-referencing)

    static let deviceId1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let deviceId2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let deviceId3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let deviceId4 = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    static let projectId1 = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let projectId2 = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let projectId3 = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    static let projectId4 = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
    static let projectId5 = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
    static let projectId6 = UUID(uuidString: "10000000-0000-0000-0000-000000000006")!

    static let chatId1 = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let chatId2 = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let chatId3 = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
    static let chatId4 = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
    static let chatId5 = UUID(uuidString: "20000000-0000-0000-0000-000000000005")!

    static let messageId1 = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let messageId2 = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    static let messageId3 = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    static let messageId4 = UUID(uuidString: "30000000-0000-0000-0000-000000000004")!
    static let messageId5 = UUID(uuidString: "30000000-0000-0000-0000-000000000005")!
    static let messageId6 = UUID(uuidString: "30000000-0000-0000-0000-000000000006")!

    static let sessionId1 = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    static let sessionId2 = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
    static let sessionId3 = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
    static let sessionId4 = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
    static let sessionId5 = UUID(uuidString: "40000000-0000-0000-0000-000000000005")!

    static let mcqId1 = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!

    // MARK: - Devices

    static let devices: [Device] = [
        Device(
            id: deviceId1,
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
            id: deviceId2,
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
            id: deviceId3,
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
            id: deviceId4,
            name: "Dev Linux Server",
            type: .linux,
            hostname: "dev-server.local",
            ipAddress: "192.168.1.200",
            status: .busy,
            lastSeen: Date(),
            osVersion: "Ubuntu 24.04",
            projectCount: 15
        ),
    ]

    // MARK: - Projects

    static let projects: [Project] = [
        Project(
            id: projectId1,
            name: "unbound-ios",
            path: "~/Code/unbound-ios",
            language: .swift,
            lastAccessed: Date(),
            chatCount: 3,
            description: "iOS app for Claude Code remote control",
            isFavorite: true
        ),
        Project(
            id: projectId2,
            name: "claude-code",
            path: "~/Code/claude-code",
            language: .typescript,
            lastAccessed: Date().addingTimeInterval(-3600),
            chatCount: 15,
            description: "Claude Code CLI tool",
            isFavorite: true
        ),
        Project(
            id: projectId3,
            name: "ml-pipeline",
            path: "~/Code/ml-pipeline",
            language: .python,
            lastAccessed: Date().addingTimeInterval(-7200),
            chatCount: 8,
            description: "Machine learning data pipeline",
            isFavorite: false
        ),
        Project(
            id: projectId4,
            name: "rust-server",
            path: "~/Code/rust-server",
            language: .rust,
            lastAccessed: Date().addingTimeInterval(-86400),
            chatCount: 2,
            description: "High-performance API server",
            isFavorite: false
        ),
        Project(
            id: projectId5,
            name: "web-dashboard",
            path: "~/Code/web-dashboard",
            language: .javascript,
            lastAccessed: Date().addingTimeInterval(-43200),
            chatCount: 6,
            description: "Admin dashboard frontend",
            isFavorite: false
        ),
        Project(
            id: projectId6,
            name: "go-microservices",
            path: "~/Code/go-microservices",
            language: .go,
            lastAccessed: Date().addingTimeInterval(-172800),
            chatCount: 4,
            description: "Microservices architecture",
            isFavorite: true
        ),
    ]

    // MARK: - Chats

    static let chats: [Chat] = [
        Chat(
            id: chatId1,
            title: "Implement device list view",
            createdAt: Date().addingTimeInterval(-3600),
            lastMessageAt: Date(),
            messageCount: 24,
            preview: "The device list is now complete with proper styling and animations...",
            status: .active
        ),
        Chat(
            id: chatId2,
            title: "Fix navigation stack issues",
            createdAt: Date().addingTimeInterval(-7200),
            lastMessageAt: Date().addingTimeInterval(-1800),
            messageCount: 12,
            preview: "I've updated the navigation to use proper path-based routing...",
            status: .completed
        ),
        Chat(
            id: chatId3,
            title: "Add dark mode support",
            createdAt: Date().addingTimeInterval(-86400),
            lastMessageAt: Date().addingTimeInterval(-43200),
            messageCount: 8,
            preview: "Dark mode is now fully implemented with semantic colors...",
            status: .completed
        ),
        Chat(
            id: chatId4,
            title: "Refactor data models",
            createdAt: Date().addingTimeInterval(-172800),
            lastMessageAt: Date().addingTimeInterval(-86400),
            messageCount: 15,
            preview: "The models have been refactored to use Codable and Hashable...",
            status: .archived
        ),
        Chat(
            id: chatId5,
            title: "Setup project architecture",
            createdAt: Date().addingTimeInterval(-259200),
            lastMessageAt: Date().addingTimeInterval(-172800),
            messageCount: 32,
            preview: "The MVVM architecture is now in place with proper separation...",
            status: .completed
        ),
    ]

    // MARK: - Messages

    static let messages: [Message] = [
        Message(
            id: messageId1,
            content: "Can you help me create a beautiful device list interface?",
            role: .user,
            timestamp: Date().addingTimeInterval(-600)
        ),
        Message(
            id: messageId2,
            content: "I'll create a polished device list interface for you. The design will include device icons, status indicators, and smooth animations. Here's the implementation:",
            role: .assistant,
            timestamp: Date().addingTimeInterval(-540),
            codeBlocks: [
                Message.CodeBlock(
                    id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!,
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
                ),
            ]
        ),
        Message(
            id: messageId3,
            content: "That looks great! Can you also add a search bar?",
            role: .user,
            timestamp: Date().addingTimeInterval(-300)
        ),
        Message(
            id: messageId4,
            content: "Of course! I'll add a searchable modifier to the list view. This will automatically add a search bar that filters devices by name or hostname.",
            role: .assistant,
            timestamp: Date().addingTimeInterval(-240)
        ),
        Message(
            id: messageId5,
            content: "Now let's add pull-to-refresh support too.",
            role: .user,
            timestamp: Date().addingTimeInterval(-120)
        ),
        Message(
            id: messageId6,
            content: "I've added the .refreshable modifier which works natively with async/await. When the user pulls down, it will call the refresh function and show a loading indicator until the async operation completes.",
            role: .assistant,
            timestamp: Date().addingTimeInterval(-60)
        ),
    ]

    // MARK: - MCQ Questions

    static let mcqQuestion: MCQQuestion = MCQQuestion(
        id: mcqId1,
        question: "How would you like me to implement this feature?",
        options: [
            MCQQuestion.MCQOption(
                label: "Add to existing file",
                description: "Modify ChatView.swift with new components",
                icon: "doc.badge.plus"
            ),
            MCQQuestion.MCQOption(
                label: "Create new files",
                description: "Create separate component files",
                icon: "folder.badge.plus"
            ),
            MCQQuestion.MCQOption(
                label: "Let Claude decide",
                description: "I'll analyze the codebase and choose the best approach",
                icon: "brain.head.profile"
            ),
        ]
    )

    static let mcqQuestionConfirmed: MCQQuestion = {
        var question = mcqQuestion
        question.selectedOptionId = question.options[0].id
        question.isConfirmed = true
        return question
    }()

    static let mcqQuestionWithCustomAnswer: MCQQuestion = MCQQuestion(
        id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
        question: "Which approach do you prefer?",
        options: [
            MCQQuestion.MCQOption(label: "Option A", description: "First option", icon: "1.circle"),
            MCQQuestion.MCQOption(label: "Option B", description: "Second option", icon: "2.circle"),
        ],
        selectedOptionId: MCQQuestion.somethingElseOption.id,
        customAnswer: "I'd like to use a combination of both approaches",
        isConfirmed: true
    )

    // MARK: - Tool Usage

    static let activeToolState = ToolUsageState(
        toolName: "Read",
        statusText: "Reading ChatView.swift",
        isActive: true,
        progress: 0.6
    )

    static let completedToolState = ToolUsageState(
        toolName: "Grep",
        statusText: "Found 12 matches",
        isActive: false
    )

    static let toolHistory: [ToolUsageState] = [
        ToolUsageState(toolName: "Read", statusText: "Reading ChatView.swift", isActive: false),
        ToolUsageState(toolName: "Glob", statusText: "Searching for related components", isActive: false),
        ToolUsageState(toolName: "Read", statusText: "Analyzing AppTheme.swift", isActive: false),
    ]

    // MARK: - Code Diffs

    static let codeDiff = CodeDiff(
        filename: "Views/Chat/Components/NewFeatureView.swift",
        language: "swift",
        hunks: [
            CodeDiff.DiffHunk(
                header: "@@ -0,0 +1,17 @@",
                lines: [
                    CodeDiff.DiffLine(content: "import SwiftUI", type: .addition, lineNumber: 1),
                    CodeDiff.DiffLine(content: "", type: .addition, lineNumber: 2),
                    CodeDiff.DiffLine(content: "struct NewFeatureView: View {", type: .addition, lineNumber: 3),
                    CodeDiff.DiffLine(content: "    @State private var isEnabled = false", type: .addition, lineNumber: 4),
                    CodeDiff.DiffLine(content: "", type: .addition, lineNumber: 5),
                    CodeDiff.DiffLine(content: "    var body: some View {", type: .addition, lineNumber: 6),
                    CodeDiff.DiffLine(content: "        VStack(spacing: AppTheme.spacingM) {", type: .addition, lineNumber: 7),
                    CodeDiff.DiffLine(content: "            Text(\"New Feature\")", type: .addition, lineNumber: 8),
                    CodeDiff.DiffLine(content: "                .font(.headline)", type: .addition, lineNumber: 9),
                    CodeDiff.DiffLine(content: "                .foregroundStyle(AppTheme.accent)", type: .addition, lineNumber: 10),
                    CodeDiff.DiffLine(content: "", type: .addition, lineNumber: 11),
                    CodeDiff.DiffLine(content: "            Toggle(\"Enable\", isOn: $isEnabled)", type: .addition, lineNumber: 12),
                    CodeDiff.DiffLine(content: "                .tint(AppTheme.accent)", type: .addition, lineNumber: 13),
                    CodeDiff.DiffLine(content: "        }", type: .addition, lineNumber: 14),
                    CodeDiff.DiffLine(content: "        .padding()", type: .addition, lineNumber: 15),
                    CodeDiff.DiffLine(content: "    }", type: .addition, lineNumber: 16),
                    CodeDiff.DiffLine(content: "}", type: .addition, lineNumber: 17),
                ]
            ),
        ]
    )

    static let mixedCodeDiff = CodeDiff(
        filename: "Services/AuthService.swift",
        language: "swift",
        hunks: [
            CodeDiff.DiffHunk(
                header: "@@ -42,8 +42,12 @@",
                lines: [
                    CodeDiff.DiffLine(content: "    func refreshToken() async throws {", type: .context, lineNumber: 42),
                    CodeDiff.DiffLine(content: "        guard let session = currentSession else {", type: .context, lineNumber: 43),
                    CodeDiff.DiffLine(content: "            throw AuthError.noSession", type: .deletion, lineNumber: 44),
                    CodeDiff.DiffLine(content: "            logger.warning(\"No active session for token refresh\")", type: .addition, lineNumber: 44),
                    CodeDiff.DiffLine(content: "            throw AuthError.sessionExpired", type: .addition, lineNumber: 45),
                    CodeDiff.DiffLine(content: "        }", type: .context, lineNumber: 46),
                    CodeDiff.DiffLine(content: "", type: .context, lineNumber: 47),
                    CodeDiff.DiffLine(content: "        let newToken = try await client.auth.refreshSession()", type: .deletion, lineNumber: 48),
                    CodeDiff.DiffLine(content: "        do {", type: .addition, lineNumber: 48),
                    CodeDiff.DiffLine(content: "            let newToken = try await client.auth.refreshSession()", type: .addition, lineNumber: 49),
                    CodeDiff.DiffLine(content: "            logger.info(\"Token refreshed successfully\")", type: .addition, lineNumber: 50),
                    CodeDiff.DiffLine(content: "        } catch {", type: .addition, lineNumber: 51),
                    CodeDiff.DiffLine(content: "            logger.error(\"Token refresh failed: \\(error)\")", type: .addition, lineNumber: 52),
                    CodeDiff.DiffLine(content: "            throw AuthError.refreshFailed(error)", type: .addition, lineNumber: 53),
                    CodeDiff.DiffLine(content: "        }", type: .addition, lineNumber: 54),
                ]
            ),
        ]
    )

    // MARK: - Active Sessions

    static let activeSessions: [ActiveSession] = [
        ActiveSession(
            id: sessionId1,
            projectName: "unbound-ios",
            chatTitle: "Implement device list view",
            deviceName: "MacBook Pro",
            status: .generating,
            progress: 0.45,
            startedAt: Date(),
            language: .swift
        ),
        ActiveSession(
            id: sessionId2,
            projectName: "claude-code",
            chatTitle: "Fix navigation stack issues",
            deviceName: "MacBook Pro",
            status: .prReady,
            progress: 1.0,
            startedAt: Date().addingTimeInterval(-300),
            language: .typescript
        ),
        ActiveSession(
            id: sessionId3,
            projectName: "ml-pipeline",
            chatTitle: "Add data validation",
            deviceName: "Mac Mini",
            status: .merged,
            progress: 1.0,
            startedAt: Date().addingTimeInterval(-600),
            language: .python
        ),
        ActiveSession(
            id: sessionId4,
            projectName: "web-dashboard",
            chatTitle: "Update auth flow",
            deviceName: "MacBook Pro",
            status: .reviewing,
            progress: 0.0,
            startedAt: Date().addingTimeInterval(-120),
            language: .javascript
        ),
        ActiveSession(
            id: sessionId5,
            projectName: "rust-server",
            chatTitle: "Optimize database queries",
            deviceName: "Linux Server",
            status: .failed,
            progress: 0.0,
            startedAt: Date().addingTimeInterval(-900),
            language: .rust
        ),
    ]

    // MARK: - Rich Message Thread (with MCQ, tools, diffs)

    static let richMessages: [Message] = [
        Message(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
            content: "Can you help me add pull-to-refresh to the device list?",
            role: .user,
            timestamp: Date().addingTimeInterval(-600)
        ),
        Message(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!,
            content: "",
            role: .assistant,
            timestamp: Date().addingTimeInterval(-580),
            richContent: .mcqQuestion(mcqQuestion)
        ),
        Message(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000003")!,
            content: "I've analyzed the codebase and here's the implementation:",
            role: .assistant,
            timestamp: Date().addingTimeInterval(-500)
        ),
        Message(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000004")!,
            content: "",
            role: .assistant,
            timestamp: Date().addingTimeInterval(-480),
            richContent: .codeDiff(codeDiff)
        ),
    ]

    // MARK: - Helper Functions

    static func projects(for device: Device) -> [Project] {
        Array(projects.prefix(min(device.projectCount, projects.count)))
    }

    static func chats(for project: Project) -> [Chat] {
        Array(chats.prefix(min(project.chatCount, chats.count)))
    }
}

#endif
