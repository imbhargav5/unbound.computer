//
//  FakeData.swift
//  unbound-macos
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import Foundation

// MARK: - Fake Data Provider

struct FakeData {
    // MARK: - Workspaces (for UI previews)

    static let workspaces: [Workspace] = [
        Workspace(
            name: "panda",
            status: .active,
            repositories: [],
            isExpanded: true
        ),
        Workspace(
            name: "wolf",
            status: .active,
            repositories: [
                Repository(
                    name: "wolf/feature-auth",
                    branchName: "seattle",
                    branches: [
                        Branch(name: "feature-auth", type: .pullRequest, additions: 1251, deletions: 98, prNumber: 11, isArchived: false)
                    ],
                    lastUpdated: "PR #11",
                    keyboardShortcut: "7"
                )
            ],
            isExpanded: true
        ),
        Workspace(
            name: "falcon",
            status: .active,
            repositories: [
                Repository(
                    name: "falcon/api-refactor",
                    branchName: "tokyo",
                    branches: [
                        Branch(name: "api-refactor", type: .pullRequest, additions: 3119, deletions: 52, prNumber: 9, isArchived: false)
                    ],
                    lastUpdated: "PR #9",
                    keyboardShortcut: "8"
                ),
                Repository(
                    name: "falcon/main",
                    branchName: "nairobi",
                    branches: [],
                    lastUpdated: "6d ago",
                    keyboardShortcut: "9"
                )
            ],
            isExpanded: true
        ),
        Workspace(
            name: "orca",
            status: .active,
            repositories: [],
            isExpanded: false
        ),
        Workspace(
            name: "otter",
            status: .active,
            repositories: [
                Repository(
                    name: "otter",
                    branchName: "main",
                    branches: [],
                    isSelected: true,
                    lastUpdated: "1mo ago"
                )
            ],
            isExpanded: true
        ),
        Workspace(
            name: "tiger",
            status: .active,
            repositories: [],
            isExpanded: false
        ),
        Workspace(
            name: "raven",
            status: .active,
            repositories: [
                Repository(
                    name: "raven/dev-signing",
                    branchName: "london",
                    branches: [],
                    lastUpdated: "6d ago"
                )
            ],
            isExpanded: true
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

    // MARK: - Sample Chat

    static let sampleChatTabs: [ChatTab] = [
        ChatTab(title: "Untitled"),
        ChatTab(title: "Untitled")
    ]

    // MARK: - Welcome Message

    static func welcomeMessage(for repoPath: String) -> String {
        "New chat in /\(repoPath)"
    }

    static let tipMessage = "Tip: O to open this workspace in your default app"
}
