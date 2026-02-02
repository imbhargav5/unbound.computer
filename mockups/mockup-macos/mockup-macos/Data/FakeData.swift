//
//  FakeData.swift
//  mockup-macos
//
//  Mock data for UI previews and testing
//

import Foundation

// MARK: - Fake Data Provider

struct FakeData {
    // MARK: - Sample Repository IDs

    static let sampleRepositoryId1 = UUID()
    static let sampleRepositoryId2 = UUID()

    // MARK: - Repositories

    static let repositories: [Repository] = [
        Repository(
            id: sampleRepositoryId1,
            path: "/Users/developer/projects/unbound",
            name: "unbound",
            isGitRepository: true,
            defaultBranch: "main"
        ),
        Repository(
            id: sampleRepositoryId2,
            path: "/Users/developer/projects/awesome-app",
            name: "awesome-app",
            isGitRepository: true,
            defaultBranch: "main"
        )
    ]

    // MARK: - Sessions

    static let sessions: [Session] = [
        Session(
            repositoryId: sampleRepositoryId1,
            title: "Feature development",
            status: .active
        ),
        Session(
            repositoryId: sampleRepositoryId1,
            title: "Bug fix discussion",
            status: .active
        ),
        Session(
            repositoryId: sampleRepositoryId1,
            title: "Refactoring ideas",
            status: .active
        ),
        Session(
            repositoryId: sampleRepositoryId2,
            title: "API integration",
            status: .active
        ),
        Session(
            repositoryId: sampleRepositoryId2,
            title: "UI improvements",
            status: .active
        )
    ]

    // MARK: - Sample Messages

    static let sampleMessages: [ChatMessage] = [
        ChatMessage(role: .user, text: "Help me understand this code"),
        ChatMessage(
            role: .assistant,
            content: [.text(TextContent(text: "I'd be happy to help! Which part would you like me to explain?"))]
        ),
        ChatMessage(role: .user, text: "Can you refactor the authentication module to use async/await?"),
        ChatMessage(
            role: .assistant,
            content: [
                .text(TextContent(text: "I'll help you refactor the authentication module. Let me analyze the current implementation and convert it to use async/await.")),
                .toolUse(ToolUse(
                    toolName: "Read",
                    input: "auth/login.swift",
                    status: .completed
                )),
                .text(TextContent(text: "Here's the refactored code using modern async/await patterns:")),
                .codeBlock(CodeBlock(
                    language: "swift",
                    code: """
                    func authenticate(email: String, password: String) async throws -> User {
                        let credentials = Credentials(email: email, password: password)
                        let response = try await apiClient.post("/auth/login", body: credentials)
                        return try response.decode(User.self)
                    }
                    """,
                    filename: "auth/login.swift"
                ))
            ]
        )
    ]

    // MARK: - File Tree

    static let fileTree: [FileItem] = [
        FileItem(name: "apps", type: .folder, children: [
            FileItem(name: "web", type: .folder),
            FileItem(name: "mobile", type: .folder),
            FileItem(name: "desktop", type: .folder)
        ]),
        FileItem(name: "docs", type: .folder, children: [
            FileItem(name: "README.md", type: .markdown),
            FileItem(name: "CONTRIBUTING.md", type: .markdown)
        ]),
        FileItem(name: "packages", type: .folder, children: [
            FileItem(name: "core", type: .folder),
            FileItem(name: "utils", type: .folder),
            FileItem(name: "ui", type: .folder)
        ]),
        FileItem(name: "scripts", type: .folder, children: [
            FileItem(name: "build.sh", type: .file),
            FileItem(name: "deploy.sh", type: .file)
        ]),
        FileItem(name: ".git", type: .gitFolder),
        FileItem(name: ".gitignore", type: .gitIgnore),
        FileItem(name: "LICENSE", type: .license),
        FileItem(name: "package.json", type: .json),
        FileItem(name: "pnpm-lock.yaml", type: .yaml),
        FileItem(name: "pnpm-workspace.yaml", type: .yaml),
        FileItem(name: "turbo.json", type: .json)
    ]

    // MARK: - Git Status Files

    static let changedFiles: [GitStatusFile] = [
        GitStatusFile(path: "src/auth/login.swift", status: .modified),
        GitStatusFile(path: "src/models/User.swift", status: .modified),
        GitStatusFile(path: "src/api/endpoints.swift", status: .added),
        GitStatusFile(path: "tests/auth_tests.swift", status: .added)
    ]

    // MARK: - Git Commits

    static let commits: [GitCommit] = [
        GitCommit(
            hash: "abc123def456789",
            message: "feat: Add async authentication",
            author: "developer@example.com",
            date: Date().addingTimeInterval(-3600)
        ),
        GitCommit(
            hash: "def456ghi789012",
            message: "fix: Handle token expiration",
            author: "developer@example.com",
            date: Date().addingTimeInterval(-7200)
        ),
        GitCommit(
            hash: "ghi789jkl012345",
            message: "refactor: Clean up API client",
            author: "developer@example.com",
            date: Date().addingTimeInterval(-86400)
        )
    ]

    // MARK: - Welcome Message

    static func welcomeMessage(for repoPath: String) -> String {
        "New chat in /\(repoPath)"
    }

    static let tipMessage = "Tip: O to open this session in your default app"

    // MARK: - Tool Use Examples

    static let sampleToolUses: [ToolUse] = [
        ToolUse(
            toolName: "Read",
            input: "src/models/User.swift",
            output: "File contents here...",
            status: .completed
        ),
        ToolUse(
            toolName: "Edit",
            input: "{ \"file\": \"src/auth/login.swift\", \"old\": \"...\", \"new\": \"...\" }",
            status: .running
        ),
        ToolUse(
            toolName: "Bash",
            input: "swift test",
            output: "All tests passed!",
            status: .completed
        )
    ]

    // MARK: - Todo List Example

    static let sampleTodoList = TodoList(items: [
        TodoItem(content: "Refactor authentication module", status: .completed),
        TodoItem(content: "Add unit tests", status: .inProgress),
        TodoItem(content: "Update documentation", status: .pending),
        TodoItem(content: "Code review", status: .pending)
    ])
}
