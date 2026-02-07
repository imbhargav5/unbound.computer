//
//  PreviewData.swift
//  unbound-macos
//
//  Rich fake data for Xcode Canvas previews.
//  Provides realistic data sets for all model types so that
//  #Preview blocks render with populated, meaningful UI.
//

#if DEBUG

import Foundation

// MARK: - Preview Data

enum PreviewData {

    // MARK: - Stable Identifiers (for cross-referencing)

    static let repoId1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let repoId2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let repoId3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    static let sessionId1 = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let sessionId2 = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let sessionId3 = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    static let sessionId4 = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
    static let sessionId5 = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!

    // MARK: - Repositories

    static let repositories: [Repository] = [
        Repository(
            id: repoId1,
            path: "/Users/dev/Code/unbound.computer",
            name: "unbound.computer",
            lastAccessed: Date(),
            addedAt: Date().addingTimeInterval(-86400 * 30),
            isGitRepository: true,
            defaultBranch: "main",
            defaultRemote: "origin"
        ),
        Repository(
            id: repoId2,
            path: "/Users/dev/Code/piccolo",
            name: "piccolo",
            lastAccessed: Date().addingTimeInterval(-3600),
            addedAt: Date().addingTimeInterval(-86400 * 60),
            isGitRepository: true,
            defaultBranch: "main",
            defaultRemote: "origin"
        ),
        Repository(
            id: repoId3,
            path: "/Users/dev/Code/dotfiles",
            name: "dotfiles",
            lastAccessed: Date().addingTimeInterval(-86400 * 2),
            addedAt: Date().addingTimeInterval(-86400 * 120),
            isGitRepository: true,
            defaultBranch: "master",
            defaultRemote: "origin"
        ),
    ]

    // MARK: - Sessions

    static let sessions: [UUID: [Session]] = [
        repoId1: [
            Session(
                id: sessionId1,
                repositoryId: repoId1,
                title: "Implement WebSocket relay",
                claudeSessionId: "claude-session-abc123",
                status: .active,
                isWorktree: false,
                createdAt: Date().addingTimeInterval(-7200),
                lastAccessed: Date()
            ),
            Session(
                id: sessionId2,
                repositoryId: repoId1,
                title: "Fix auth token refresh",
                status: .active,
                isWorktree: true,
                worktreePath: "/Users/dev/Code/unbound.computer/.sessions/fix-auth",
                createdAt: Date().addingTimeInterval(-86400),
                lastAccessed: Date().addingTimeInterval(-1800)
            ),
            Session(
                id: sessionId3,
                repositoryId: repoId1,
                title: "Refactor IPC protocol",
                status: .archived,
                isWorktree: true,
                worktreePath: "/Users/dev/Code/unbound.computer/.sessions/refactor-ipc",
                createdAt: Date().addingTimeInterval(-86400 * 3),
                lastAccessed: Date().addingTimeInterval(-86400 * 2)
            ),
        ],
        repoId2: [
            Session(
                id: sessionId4,
                repositoryId: repoId2,
                title: "Add rebase support",
                status: .active,
                createdAt: Date().addingTimeInterval(-3600),
                lastAccessed: Date().addingTimeInterval(-600)
            ),
        ],
        repoId3: [
            Session(
                id: sessionId5,
                repositoryId: repoId3,
                title: "Update zsh config",
                status: .active,
                createdAt: Date().addingTimeInterval(-86400),
                lastAccessed: Date().addingTimeInterval(-43200)
            ),
        ],
    ]

    /// Flat list of all sessions for convenience
    static let allSessions: [Session] = sessions.values.flatMap { $0 }

    // MARK: - Git Commits

    static let commits: [GitCommit] = {
        let now = Int64(Date().timeIntervalSince1970)
        return [
            GitCommit(
                oid: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
                shortOid: "a1b2c3d",
                message: "feat: add WebSocket relay connection pooling\n\nImplement connection pooling for relay WebSocket connections to reduce\nlatency on reconnect. Uses LRU eviction with configurable max connections.",
                summary: "feat: add WebSocket relay connection pooling",
                authorName: "Bhargav Ponnapalli",
                authorEmail: "bhargav@unbound.computer",
                authorTime: now - 300,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 300,
                parentOids: ["b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"]
            ),
            GitCommit(
                oid: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3",
                shortOid: "b2c3d4e",
                message: "fix: handle daemon disconnect during file save\n\nCo-Authored-By: Claude <noreply@anthropic.com>",
                summary: "fix: handle daemon disconnect during file save",
                authorName: "Bhargav Ponnapalli",
                authorEmail: "bhargav@unbound.computer",
                authorTime: now - 1800,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 1800,
                parentOids: ["c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"]
            ),
            GitCommit(
                oid: "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
                shortOid: "c3d4e5f",
                message: "Merge branch 'feature/git-push' into main",
                summary: "Merge branch 'feature/git-push' into main",
                authorName: "Bhargav Ponnapalli",
                authorEmail: "bhargav@unbound.computer",
                authorTime: now - 3600,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 3600,
                parentOids: [
                    "d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5",
                    "e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6",
                ]
            ),
            GitCommit(
                oid: "d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5",
                shortOid: "d4e5f6a",
                message: "refactor: extract IPC handler registration into modules",
                summary: "refactor: extract IPC handler registration into modules",
                authorName: "Bhargav Ponnapalli",
                authorEmail: "bhargav@unbound.computer",
                authorTime: now - 7200,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 7200,
                parentOids: ["f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"]
            ),
            GitCommit(
                oid: "e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6",
                shortOid: "e5f6a1b",
                message: "feat: implement git push via libgit2\n\nAdd push support to piccolo crate using libgit2 remote callbacks.\nSupports SSH and HTTPS authentication.",
                summary: "feat: implement git push via libgit2",
                authorName: "Bhargav Ponnapalli",
                authorEmail: "bhargav@unbound.computer",
                authorTime: now - 5400,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 5400,
                parentOids: ["f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"]
            ),
            GitCommit(
                oid: "f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                shortOid: "f6a1b2c",
                message: "chore: update dependencies and lock file",
                summary: "chore: update dependencies and lock file",
                authorName: "Bhargav Ponnapalli",
                authorEmail: "bhargav@unbound.computer",
                authorTime: now - 10800,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 10800,
                parentOids: ["a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"]
            ),
            GitCommit(
                oid: "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1",
                shortOid: "a1a1a1a",
                message: "feat: add commit graph visualization to right sidebar\n\nRender commit history as a visual graph with branch lines and merge\npoints. Uses column-based layout similar to `git log --graph`.",
                summary: "feat: add commit graph visualization to right sidebar",
                authorName: "Bhargav Ponnapalli",
                authorEmail: "bhargav@unbound.computer",
                authorTime: now - 14400,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 14400,
                parentOids: ["b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"]
            ),
            GitCommit(
                oid: "b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1",
                shortOid: "b1b1b1b",
                message: "docs: update README with architecture diagram",
                summary: "docs: update README with architecture diagram",
                authorName: "Claude",
                authorEmail: "noreply@anthropic.com",
                authorTime: now - 21600,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 21600,
                parentOids: ["c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1"]
            ),
            GitCommit(
                oid: "c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1",
                shortOid: "c1c1c1c",
                message: "Initial commit",
                summary: "Initial commit",
                authorName: "Bhargav Ponnapalli",
                authorEmail: "bhargav@unbound.computer",
                authorTime: now - 86400,
                committerName: "Bhargav Ponnapalli",
                committerTime: now - 86400,
                parentOids: []
            ),
        ]
    }()

    // MARK: - Git Branches

    static let localBranches: [GitBranch] = [
        GitBranch(
            name: "main",
            isCurrent: true,
            isRemote: false,
            upstream: "origin/main",
            ahead: 2,
            behind: 0,
            headOid: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        ),
        GitBranch(
            name: "feature/websocket-relay",
            isCurrent: false,
            isRemote: false,
            upstream: "origin/feature/websocket-relay",
            ahead: 1,
            behind: 3,
            headOid: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        ),
        GitBranch(
            name: "fix/auth-refresh",
            isCurrent: false,
            isRemote: false,
            upstream: nil,
            ahead: 0,
            behind: 0,
            headOid: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        ),
        GitBranch(
            name: "experiment/swift-testing",
            isCurrent: false,
            isRemote: false,
            upstream: nil,
            ahead: 0,
            behind: 0,
            headOid: "d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5"
        ),
    ]

    static let remoteBranches: [GitBranch] = [
        GitBranch(
            name: "origin/main",
            isCurrent: false,
            isRemote: true,
            upstream: nil,
            ahead: 0,
            behind: 0,
            headOid: "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
        ),
        GitBranch(
            name: "origin/feature/websocket-relay",
            isCurrent: false,
            isRemote: true,
            upstream: nil,
            ahead: 0,
            behind: 0,
            headOid: "e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"
        ),
    ]

    // MARK: - Git Status

    static let gitStatusFiles: [GitStatusFile] = [
        GitStatusFile(path: "apps/macos/unbound-macos/Views/Workspace/ChatPanel.swift", status: .modified, staged: true, additions: 45, deletions: 12),
        GitStatusFile(path: "apps/macos/unbound-macos/ViewModels/GitViewModel.swift", status: .modified, staged: true, additions: 23, deletions: 8),
        GitStatusFile(path: "apps/macos/unbound-macos/Services/Relay/RelayClient.swift", status: .added, staged: true, additions: 156, deletions: 0),
        GitStatusFile(path: "apps/daemon/crates/piccolo/src/operations.rs", status: .modified, staged: false, additions: 34, deletions: 19),
        GitStatusFile(path: "apps/daemon/crates/daemon-bin/src/ipc/handlers/git.rs", status: .modified, staged: false, additions: 12, deletions: 4),
        GitStatusFile(path: "apps/macos/unbound-macos/Models/RelayModels.swift", status: .added, staged: false, additions: 89, deletions: 0),
        GitStatusFile(path: "apps/macos/unbound-macos/Components/ToolViews/NewToolView.swift", status: .untracked, staged: false),
        GitStatusFile(path: "docs/RELAY_PROTOCOL.md", status: .untracked, staged: false),
        GitStatusFile(path: "apps/macos/unbound-macos/Services/Legacy/OldSyncService.swift", status: .deleted, staged: false, additions: 0, deletions: 234),
    ]

    static let gitStatus = GitStatusResult(
        files: gitStatusFiles,
        branch: "main",
        isClean: false
    )

    // MARK: - Chat Messages

    static let chatMessages: [ChatMessage] = [
        ChatMessage(
            role: .user,
            text: "I need to implement a WebSocket relay for real-time session sharing between devices. The relay should handle connection pooling and automatic reconnection.",
            sequenceNumber: 1
        ),
        ChatMessage(
            role: .assistant,
            content: [
                .text(TextContent(text: "I'll help you implement the WebSocket relay. Let me start by examining the current networking architecture and then build the relay client.\n\nFirst, let me look at the existing services structure:")),
                .toolUse(ToolUse(
                    toolUseId: "tool_01",
                    toolName: "Read",
                    input: "{\"file_path\": \"apps/macos/unbound-macos/Services/\"}",
                    output: "Directory listing:\n  Daemon/\n  Session/\n  Auth/",
                    status: .completed
                )),
                .toolUse(ToolUse(
                    toolUseId: "tool_02",
                    toolName: "Grep",
                    input: "{\"pattern\": \"WebSocket|URLSessionWebSocketTask\", \"path\": \"apps/macos/\"}",
                    output: "apps/macos/unbound-macos/Services/Daemon/DaemonClient.swift:42: // WebSocket connection",
                    status: .completed
                )),
                .text(TextContent(text: "I can see the project already uses WebSocket connections for the daemon IPC. I'll create a new `RelayClient` that follows the same patterns. Here's my plan:")),
                .todoList(TodoList(items: [
                    TodoItem(content: "Create RelayModels.swift with connection types", status: .completed),
                    TodoItem(content: "Implement RelayClient with connection pooling", status: .completed),
                    TodoItem(content: "Add automatic reconnection with exponential backoff", status: .inProgress),
                    TodoItem(content: "Write relay message serialization", status: .pending),
                    TodoItem(content: "Integrate with SessionStateManager", status: .pending),
                ])),
            ],
            sequenceNumber: 2
        ),
        ChatMessage(
            role: .assistant,
            content: [
                .text(TextContent(text: "Let me create the relay models first:")),
                .fileChange(FileChange(
                    filePath: "apps/macos/unbound-macos/Models/RelayModels.swift",
                    changeType: .created,
                    diff: """
                    + struct RelayConnection: Identifiable {
                    +     let id: UUID
                    +     let deviceId: String
                    +     let sessionId: UUID
                    +     var state: ConnectionState
                    + }
                    """,
                    linesAdded: 89,
                    linesRemoved: 0
                )),
                .codeBlock(CodeBlock(
                    language: "swift",
                    code: """
                    @Observable
                    class RelayClient {
                        private var connections: [UUID: URLSessionWebSocketTask] = [:]
                        private let maxConnections = 5

                        func connect(to sessionId: UUID) async throws {
                            let url = relayURL(for: sessionId)
                            let task = session.webSocketTask(with: url)
                            task.resume()
                            connections[sessionId] = task
                        }
                    }
                    """,
                    filename: "RelayClient.swift"
                )),
            ],
            sequenceNumber: 3
        ),
        ChatMessage(
            role: .user,
            text: "Looks good! Can you also add error handling for when the relay server is unreachable?",
            sequenceNumber: 4
        ),
        ChatMessage(
            role: .assistant,
            content: [
                .text(TextContent(text: "Absolutely. I'll add robust error handling with categorized error types and user-facing error messages. Let me update the `RelayClient`:")),
                .toolUse(ToolUse(
                    toolUseId: "tool_03",
                    toolName: "Edit",
                    input: "{\"file_path\": \"apps/macos/unbound-macos/Services/Relay/RelayClient.swift\"}",
                    output: "File edited successfully",
                    status: .completed
                )),
                .subAgentActivity(SubAgentActivity(
                    parentToolUseId: "task_01",
                    subagentType: "Explore",
                    description: "Search error handling patterns",
                    tools: [
                        ToolUse(toolUseId: "sub_tool_01", parentToolUseId: "task_01", toolName: "Grep", input: "{\"pattern\": \"enum.*Error.*: Error\"}", status: .completed),
                        ToolUse(toolUseId: "sub_tool_02", parentToolUseId: "task_01", toolName: "Read", input: "{\"file_path\": \"DaemonError.swift\"}", status: .completed),
                    ],
                    status: .completed,
                    result: "Found DaemonError pattern with categorized cases and localizedDescription"
                )),
                .text(TextContent(text: "I've added a `RelayError` enum following the same pattern as `DaemonError`, with specific cases for network failures, authentication issues, and connection limits. The client now catches these and surfaces them via the `@Observable` `lastError` property.")),
            ],
            sequenceNumber: 5
        ),
    ]

    // MARK: - Active Tool State (for "Claude is working" previews)

    static let activeTools: [ActiveTool] = [
        ActiveTool(id: "active_01", name: "Read", inputPreview: "apps/macos/unbound-macos/Services/Relay/RelayClient.swift", status: .running),
    ]

    static let activeSubAgents: [ActiveSubAgent] = [
        ActiveSubAgent(
            id: "agent_01",
            subagentType: "Explore",
            description: "Analyze relay protocol patterns",
            childTools: [
                ActiveTool(id: "agent_tool_01", name: "Grep", inputPreview: "WebSocket.*connect", status: .completed),
                ActiveTool(id: "agent_tool_02", name: "Read", inputPreview: "DaemonClient.swift", status: .completed),
                ActiveTool(id: "agent_tool_03", name: "Bash", inputPreview: "cargo test -p piccolo", status: .running),
            ],
            status: .running
        ),
    ]

    static let toolHistory: [ToolHistoryEntry] = [
        ToolHistoryEntry(
            tools: [
                ActiveTool(id: "hist_01", name: "Read", inputPreview: "Services/Daemon/DaemonClient.swift", status: .completed),
                ActiveTool(id: "hist_02", name: "Grep", inputPreview: "WebSocket|URLSessionWebSocketTask", status: .completed),
            ],
            subAgent: nil,
            afterMessageIndex: 1
        ),
    ]

    // MARK: - Editor Tabs

    static let editorTabs: [EditorTab] = [
        EditorTab(
            kind: .file,
            path: "Services/Relay/RelayClient.swift",
            fullPath: "/Users/dev/Code/unbound.computer/apps/macos/unbound-macos/Services/Relay/RelayClient.swift",
            sessionId: sessionId1
        ),
        EditorTab(kind: .diff, path: "ViewModels/GitViewModel.swift"),
        EditorTab(
            kind: .file,
            path: "Models/RelayModels.swift",
            fullPath: "/Users/dev/Code/unbound.computer/apps/macos/unbound-macos/Models/RelayModels.swift",
            sessionId: sessionId1
        ),
    ]

    // MARK: - Sample Editor Content

    static let sampleSwiftCode = """
    import Foundation
    import Logging

    private let logger = Logger(label: "app.relay")

    @Observable
    class RelayClient {
        private var connections: [UUID: URLSessionWebSocketTask] = [:]
        private let maxConnections = 5
        private let reconnectDelay: TimeInterval = 2.0

        enum RelayError: Error, LocalizedError {
            case serverUnreachable(String)
            case connectionPoolExhausted
            case authenticationFailed
            case messageTooLarge(Int)

            var errorDescription: String? {
                switch self {
                case .serverUnreachable(let host):
                    return "Cannot reach relay server at \\(host)"
                case .connectionPoolExhausted:
                    return "Maximum number of connections reached"
                case .authenticationFailed:
                    return "Relay authentication failed"
                case .messageTooLarge(let size):
                    return "Message exceeds maximum size (\\(size) bytes)"
                }
            }
        }

        func connect(to sessionId: UUID) async throws {
            guard connections.count < maxConnections else {
                throw RelayError.connectionPoolExhausted
            }
            let url = relayURL(for: sessionId)
            let task = session.webSocketTask(with: url)
            task.resume()
            connections[sessionId] = task
            logger.info("Connected to relay for session \\(sessionId)")
        }
    }
    """

    // MARK: - File Tree

    static let fileTree: [FileItem] = [
        FileItem(
            path: "apps",
            name: "apps",
            type: .folder,
            children: [
                FileItem(
                    path: "apps/macos",
                    name: "macos",
                    type: .folder,
                    children: [
                        FileItem(
                            path: "apps/macos/unbound-macos",
                            name: "unbound-macos",
                            type: .folder,
                            children: [
                                FileItem(path: "apps/macos/unbound-macos/Views", name: "Views", type: .folder, isDirectory: true, childrenLoaded: false, hasChildrenHint: true),
                                FileItem(path: "apps/macos/unbound-macos/ViewModels", name: "ViewModels", type: .folder, isDirectory: true, childrenLoaded: false, hasChildrenHint: true),
                                FileItem(path: "apps/macos/unbound-macos/Models", name: "Models", type: .folder, isDirectory: true, childrenLoaded: false, hasChildrenHint: true),
                                FileItem(
                                    path: "apps/macos/unbound-macos/Services",
                                    name: "Services",
                                    type: .folder,
                                    children: [
                                        FileItem(
                                            path: "apps/macos/unbound-macos/Services/Relay",
                                            name: "Relay",
                                            type: .folder,
                                            children: [
                                                FileItem(path: "apps/macos/unbound-macos/Services/Relay/RelayClient.swift", name: "RelayClient.swift", type: .swift, gitStatus: .staged, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
                                            ],
                                            isDirectory: true,
                                            childrenLoaded: true,
                                            hasChildrenHint: true
                                        ),
                                        FileItem(path: "apps/macos/unbound-macos/Services/Daemon", name: "Daemon", type: .folder, isDirectory: true, childrenLoaded: false, hasChildrenHint: true),
                                        FileItem(path: "apps/macos/unbound-macos/Services/Session", name: "Session", type: .folder, isDirectory: true, childrenLoaded: false, hasChildrenHint: true),
                                    ],
                                    isDirectory: true,
                                    childrenLoaded: true,
                                    hasChildrenHint: true
                                ),
                                FileItem(path: "apps/macos/unbound-macos/Components", name: "Components", type: .folder, isDirectory: true, childrenLoaded: false, hasChildrenHint: true),
                                FileItem(path: "apps/macos/unbound-macos/Data", name: "Data", type: .folder, isDirectory: true, childrenLoaded: false, hasChildrenHint: true),
                            ],
                            isDirectory: true,
                            childrenLoaded: true,
                            hasChildrenHint: true
                        ),
                    ],
                    isDirectory: true,
                    childrenLoaded: true,
                    hasChildrenHint: true
                ),
                FileItem(path: "apps/daemon", name: "daemon", type: .folder, isDirectory: true, childrenLoaded: false, hasChildrenHint: true),
            ],
            isDirectory: true,
            childrenLoaded: true,
            hasChildrenHint: true
        ),
        FileItem(
            path: "docs",
            name: "docs",
            type: .folder,
            children: [
                FileItem(path: "docs/README.md", name: "README.md", type: .markdown, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
                FileItem(path: "docs/CONTRIBUTING.md", name: "CONTRIBUTING.md", type: .markdown, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
                FileItem(path: "docs/RELAY_PROTOCOL.md", name: "RELAY_PROTOCOL.md", type: .markdown, gitStatus: .untracked, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
            ],
            isDirectory: true,
            childrenLoaded: true,
            hasChildrenHint: true
        ),
        FileItem(path: "package.json", name: "package.json", type: .json, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
        FileItem(path: "Cargo.toml", name: "Cargo.toml", type: .file, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
        FileItem(path: ".gitignore", name: ".gitignore", type: .gitIgnore, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
        FileItem(path: "LICENSE", name: "LICENSE", type: .license, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
    ]
}

#endif
