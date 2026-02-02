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
            author: "Sarah Chen",
            date: Date().addingTimeInterval(-3600)
        ),
        GitCommit(
            hash: "def456ghi789012",
            message: "fix: Handle token expiration edge case",
            author: "Sarah Chen",
            date: Date().addingTimeInterval(-7200)
        ),
        GitCommit(
            hash: "ghi789jkl012345",
            message: "refactor: Extract validation logic to utils",
            author: "Alex Kim",
            date: Date().addingTimeInterval(-18000)
        ),
        GitCommit(
            hash: "jkl012mno345678",
            message: "docs: Update API documentation",
            author: "Jordan Lee",
            date: Date().addingTimeInterval(-86400)
        ),
        GitCommit(
            hash: "mno345pqr678901",
            message: "chore: Upgrade dependencies to latest",
            author: "Sarah Chen",
            date: Date().addingTimeInterval(-172800)
        ),
        GitCommit(
            hash: "pqr678stu901234",
            message: "feat: Implement OAuth2 flow",
            author: "Alex Kim",
            date: Date().addingTimeInterval(-259200)
        ),
        GitCommit(
            hash: "stu901vwx234567",
            message: "test: Add integration tests for auth",
            author: "Jordan Lee",
            date: Date().addingTimeInterval(-345600)
        ),
        GitCommit(
            hash: "vwx234yza567890",
            message: "fix: Resolve memory leak in session manager",
            author: "Sarah Chen",
            date: Date().addingTimeInterval(-432000)
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

    // MARK: - Sub-Agent Activity Examples

    /// Sample Explore agent activity (completed)
    static let exploreAgentCompleted = SubAgentActivity(
        parentToolUseId: "explore_001",
        subagentType: "Explore",
        description: "Search codebase for authentication patterns",
        tools: [
            ToolUse(
                toolName: "Glob",
                input: "**/auth/**/*.swift",
                output: "Found 12 files",
                status: .completed
            ),
            ToolUse(
                toolName: "Read",
                input: "src/auth/AuthManager.swift",
                output: "File contents...",
                status: .completed
            ),
            ToolUse(
                toolName: "Grep",
                input: "func authenticate",
                output: "3 matches found",
                status: .completed
            ),
            ToolUse(
                toolName: "Read",
                input: "src/auth/TokenStore.swift",
                output: "File contents...",
                status: .completed
            )
        ],
        status: .completed,
        result: "Found authentication implementation in AuthManager.swift with JWT-based token handling. TokenStore manages secure storage."
    )

    /// Sample Explore agent activity (running)
    static let exploreAgentRunning = SubAgentActivity(
        parentToolUseId: "explore_002",
        subagentType: "Explore",
        description: "Find related UI components",
        tools: [
            ToolUse(
                toolName: "Glob",
                input: "**/Components/**/*.swift",
                output: "Found 24 files",
                status: .completed
            ),
            ToolUse(
                toolName: "Read",
                input: "src/Components/ChatView.swift",
                status: .running
            )
        ],
        status: .running
    )

    /// Sample Plan agent activity
    static let planAgentActivity = SubAgentActivity(
        parentToolUseId: "plan_001",
        subagentType: "Plan",
        description: "Design implementation strategy for dark mode",
        tools: [
            ToolUse(
                toolName: "Read",
                input: "src/Theme/Colors.swift",
                output: "File contents...",
                status: .completed
            ),
            ToolUse(
                toolName: "Glob",
                input: "**/Theme/**/*.swift",
                output: "Found 8 files",
                status: .completed
            ),
            ToolUse(
                toolName: "Read",
                input: "src/Theme/ThemeManager.swift",
                output: "File contents...",
                status: .completed
            )
        ],
        status: .completed,
        result: "Recommended approach: 1) Create DarkTheme struct, 2) Add theme toggle to ThemeManager, 3) Update all views to use dynamic colors."
    )

    /// Sample general-purpose agent activity
    static let generalAgentActivity = SubAgentActivity(
        parentToolUseId: "general_001",
        subagentType: "general-purpose",
        description: "Implement user settings persistence",
        tools: [
            ToolUse(
                toolName: "Read",
                input: "src/Settings/SettingsManager.swift",
                output: "File contents...",
                status: .completed
            ),
            ToolUse(
                toolName: "Edit",
                input: "src/Settings/SettingsManager.swift",
                output: "Changes applied",
                status: .completed
            ),
            ToolUse(
                toolName: "Write",
                input: "src/Settings/UserPreferences.swift",
                status: .running
            )
        ],
        status: .running
    )

    /// Sample Bash agent activity
    static let bashAgentActivity = SubAgentActivity(
        parentToolUseId: "bash_001",
        subagentType: "Bash",
        description: "Run tests and build project",
        tools: [
            ToolUse(
                toolName: "Bash",
                input: "swift test",
                output: "All tests passed (42 tests)",
                status: .completed
            ),
            ToolUse(
                toolName: "Bash",
                input: "swift build -c release",
                status: .running
            )
        ],
        status: .running
    )

    /// Sample messages with sub-agent activities
    static let messagesWithSubAgents: [ChatMessage] = [
        ChatMessage(role: .user, text: "Can you explore the authentication code and then plan how to add OAuth support?"),
        ChatMessage(
            role: .assistant,
            content: [
                .text(TextContent(text: "I'll explore the authentication codebase and then design a plan for OAuth implementation.")),
                .subAgentActivity(exploreAgentCompleted),
                .subAgentActivity(planAgentActivity),
                .text(TextContent(text: "Based on my analysis, here's what I found and recommend:"))
            ]
        ),
        ChatMessage(role: .user, text: "Great, now implement the first step"),
        ChatMessage(
            role: .assistant,
            content: [
                .text(TextContent(text: "I'll start implementing the OAuth configuration struct.")),
                .subAgentActivity(generalAgentActivity)
            ]
        )
    ]

    /// Sample parallel sub-agents (multiple running at once)
    static let parallelSubAgents: [SubAgentActivity] = [
        exploreAgentRunning,
        bashAgentActivity
    ]
}
