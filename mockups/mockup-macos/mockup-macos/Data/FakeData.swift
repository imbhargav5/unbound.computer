//
//  FakeData.swift
//  mockup-macos
//
//  Mock data for UI previews and testing
//

import Foundation

// MARK: - Editor File Seed

struct EditorFileSeed: Hashable {
    let path: String
    let content: String
    let language: String
}

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

    /// Main directory sessions (not in worktrees)
    static let sessions: [Session] = [
        // unbound - main directory sessions
        Session(
            repositoryId: sampleRepositoryId1,
            title: "Feature development",
            status: .active,
            isWorktree: false
        ),
        Session(
            repositoryId: sampleRepositoryId1,
            title: "Bug fix discussion",
            status: .active,
            isWorktree: false
        ),
        // unbound - worktree sessions (happy-giraffe)
        Session(
            repositoryId: sampleRepositoryId1,
            title: "OAuth implementation",
            status: .active,
            isWorktree: true,
            worktreePath: "/Users/developer/projects/unbound/happy-giraffe-08a54f"
        ),
        Session(
            repositoryId: sampleRepositoryId1,
            title: "Token refresh logic",
            status: .active,
            isWorktree: true,
            worktreePath: "/Users/developer/projects/unbound/happy-giraffe-08a54f"
        ),
        // unbound - worktree sessions (clever-penguin)
        Session(
            repositoryId: sampleRepositoryId1,
            title: "Dark mode styling",
            status: .active,
            isWorktree: true,
            worktreePath: "/Users/developer/projects/unbound/clever-penguin-3b21cd"
        ),
        // awesome-app - main directory sessions
        Session(
            repositoryId: sampleRepositoryId2,
            title: "API integration",
            status: .active,
            isWorktree: false
        ),
        Session(
            repositoryId: sampleRepositoryId2,
            title: "UI improvements",
            status: .active,
            isWorktree: false
        ),
        // awesome-app - worktree sessions
        Session(
            repositoryId: sampleRepositoryId2,
            title: "Performance tuning",
            status: .active,
            isWorktree: true,
            worktreePath: "/Users/developer/projects/awesome-app/swift-fox-9e82ab"
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

    // MARK: - Editor Seeds

    static let editorFileSeeds: [EditorFileSeed] = [
        EditorFileSeed(
            path: "src/auth/login.swift",
            content: """
            import Foundation

            class AuthManager {
                static let shared = AuthManager()

                private var currentUser: User?
                private let tokenStore = TokenStore()

                func authenticate(email: String, password: String) async throws -> User {
                    let credentials = Credentials(email: email, password: password)
                    let response = try await apiClient.post("/auth/login", body: credentials)
                    let user = try response.decode(User.self)

                    // Store the token
                    try await tokenStore.save(response.token)

                    currentUser = user
                    return user
                }

                func logout() async {
                    currentUser = nil
                    await tokenStore.clear()
                }

                var isAuthenticated: Bool {
                    currentUser != nil
                }
            }
            """,
            language: "swift"
        ),
        EditorFileSeed(
            path: "src/models/User.swift",
            content: """
            import Foundation

            struct User: Codable, Identifiable {
                let id: UUID
                let email: String
                let name: String
                let avatarURL: URL?
                let createdAt: Date

                var initials: String {
                    name.split(separator: " ")
                        .prefix(2)
                        .compactMap { $0.first }
                        .map(String.init)
                        .joined()
                }
            }
            """,
            language: "swift"
        ),
        EditorFileSeed(
            path: "src/api/endpoints.swift",
            content: """
            import Foundation

            enum APIEndpoint {
                case login
                case logout
                case user(id: UUID)
                case users

                var path: String {
                    switch self {
                    case .login: return "/auth/login"
                    case .logout: return "/auth/logout"
                    case .user(let id): return "/users/\\(id)"
                    case .users: return "/users"
                    }
                }
            }
            """,
            language: "swift"
        )
    ]

    static func editorFileSeed(for path: String) -> EditorFileSeed? {
        editorFileSeeds.first { $0.path == path }
    }

    // MARK: - Git Status Files
    // Diverse set of file statuses to demonstrate the Changes view

    static let changedFiles: [GitStatusFile] = [
        // Modified files (yellow M indicator) - with line change stats
        GitStatusFile(path: "src/auth/login.swift", status: .modified, additions: 24, deletions: 8),
        GitStatusFile(path: "src/models/User.swift", status: .modified, additions: 12, deletions: 3),
        GitStatusFile(path: "src/views/SettingsView.swift", status: .modified, additions: 156, deletions: 42),

        // Added files (green A indicator) - only additions
        GitStatusFile(path: "src/api/endpoints.swift", status: .added, additions: 87, deletions: 0),
        GitStatusFile(path: "tests/auth_tests.swift", status: .added, additions: 234, deletions: 0),

        // Deleted files (red D indicator) - only deletions
        GitStatusFile(path: "src/legacy/OldAuth.swift", status: .deleted, additions: 0, deletions: 145),

        // Renamed files (blue R indicator)
        GitStatusFile(path: "src/utils/helpers.swift", status: .renamed, additions: 5, deletions: 2),

        // Untracked files (gray U indicator) - no stats for untracked
        GitStatusFile(path: "notes.txt", status: .untracked),
        GitStatusFile(path: ".env.local", status: .untracked)
    ]

    // MARK: - Sample Diffs

    static let fileDiffsByPath: [String: FileDiff] = [
        "src/auth/login.swift": FileDiff(
            filePath: "src/auth/login.swift",
            changeType: .modified,
            hunks: [
                DiffHunk(
                    oldStart: 12,
                    oldCount: 5,
                    newStart: 12,
                    newCount: 6,
                    context: "func authenticate",
                    lines: [
                        DiffLine(type: .context, content: "    let response = try await apiClient.post(\"/auth/login\", body: credentials)", oldLineNumber: 12, newLineNumber: 12),
                        DiffLine(type: .deletion, content: "    let user = try response.decode(User.self)", oldLineNumber: 13, newLineNumber: nil),
                        DiffLine(type: .addition, content: "    let user = try response.decode(User.self)", oldLineNumber: nil, newLineNumber: 13),
                        DiffLine(type: .addition, content: "    logger.info(\"Login success\")", oldLineNumber: nil, newLineNumber: 14),
                        DiffLine(type: .context, content: "    currentUser = user", oldLineNumber: 14, newLineNumber: 15)
                    ]
                )
            ],
            linesAdded: 2,
            linesRemoved: 1
        ),
        "src/models/User.swift": FileDiff(
            filePath: "src/models/User.swift",
            changeType: .modified,
            hunks: [
                DiffHunk(
                    oldStart: 6,
                    oldCount: 4,
                    newStart: 6,
                    newCount: 5,
                    context: "struct User",
                    lines: [
                        DiffLine(type: .context, content: "    let id: UUID", oldLineNumber: 6, newLineNumber: 6),
                        DiffLine(type: .context, content: "    let email: String", oldLineNumber: 7, newLineNumber: 7),
                        DiffLine(type: .addition, content: "    let username: String", oldLineNumber: nil, newLineNumber: 8),
                        DiffLine(type: .context, content: "    let name: String", oldLineNumber: 8, newLineNumber: 9)
                    ]
                )
            ],
            linesAdded: 1,
            linesRemoved: 0
        ),
        "src/api/endpoints.swift": FileDiff(
            filePath: "src/api/endpoints.swift",
            changeType: .created,
            hunks: [
                DiffHunk(
                    oldStart: 0,
                    oldCount: 0,
                    newStart: 1,
                    newCount: 6,
                    context: "enum APIEndpoint",
                    lines: [
                        DiffLine(type: .addition, content: "enum APIEndpoint {", oldLineNumber: nil, newLineNumber: 1),
                        DiffLine(type: .addition, content: "    case login", oldLineNumber: nil, newLineNumber: 2),
                        DiffLine(type: .addition, content: "    case logout", oldLineNumber: nil, newLineNumber: 3),
                        DiffLine(type: .addition, content: "}", oldLineNumber: nil, newLineNumber: 4)
                    ]
                )
            ],
            linesAdded: 4,
            linesRemoved: 0
        )
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
