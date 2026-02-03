//
//  FakeData.swift
//  unbound-macos
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import Foundation

// MARK: - Fake Data Provider

struct FakeData {
    // MARK: - Sample Repository ID (for previews)

    static let sampleRepositoryId = UUID()

    // MARK: - Sessions (for UI previews)

    static let sessions: [Session] = [
        Session(
            repositoryId: sampleRepositoryId,
            title: "Feature development",
            status: .active
        ),
        Session(
            repositoryId: sampleRepositoryId,
            title: "Bug fix discussion",
            status: .active
        ),
        Session(
            repositoryId: sampleRepositoryId,
            title: "Refactoring ideas",
            status: .active
        )
    ]

    // MARK: - Sample Messages

    static let sampleMessages: [ChatMessage] = [
        ChatMessage(role: .user, text: "Help me understand this code"),
        ChatMessage(
            role: .assistant,
            content: [.text(TextContent(text: "I'd be happy to help! Which part would you like me to explain?"))]
        )
    ]

    // MARK: - File Tree

    static let fileTree: [FileItem] = [
        FileItem(
            path: "apps",
            name: "apps",
            type: .folder,
            children: [
                FileItem(path: "apps/web", name: "web", type: .folder, isDirectory: true, childrenLoaded: true, hasChildrenHint: false),
                FileItem(path: "apps/mobile", name: "mobile", type: .folder, isDirectory: true, childrenLoaded: true, hasChildrenHint: false),
                FileItem(path: "apps/desktop", name: "desktop", type: .folder, isDirectory: true, childrenLoaded: true, hasChildrenHint: false)
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
                FileItem(path: "docs/CONTRIBUTING.md", name: "CONTRIBUTING.md", type: .markdown, isDirectory: false, childrenLoaded: true, hasChildrenHint: false)
            ],
            isDirectory: true,
            childrenLoaded: true,
            hasChildrenHint: true
        ),
        FileItem(
            path: "packages",
            name: "packages",
            type: .folder,
            children: [
                FileItem(path: "packages/core", name: "core", type: .folder, isDirectory: true, childrenLoaded: true, hasChildrenHint: false),
                FileItem(path: "packages/utils", name: "utils", type: .folder, isDirectory: true, childrenLoaded: true, hasChildrenHint: false),
                FileItem(path: "packages/ui", name: "ui", type: .folder, isDirectory: true, childrenLoaded: true, hasChildrenHint: false)
            ],
            isDirectory: true,
            childrenLoaded: true,
            hasChildrenHint: true
        ),
        FileItem(
            path: "scripts",
            name: "scripts",
            type: .folder,
            children: [
                FileItem(path: "scripts/build.sh", name: "build.sh", type: .file, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
                FileItem(path: "scripts/deploy.sh", name: "deploy.sh", type: .file, isDirectory: false, childrenLoaded: true, hasChildrenHint: false)
            ],
            isDirectory: true,
            childrenLoaded: true,
            hasChildrenHint: true
        ),
        FileItem(path: ".git", name: ".git", type: .gitFolder, isDirectory: true, childrenLoaded: false, hasChildrenHint: false),
        FileItem(path: ".gitignore", name: ".gitignore", type: .gitIgnore, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
        FileItem(path: "LICENSE", name: "LICENSE", type: .license, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
        FileItem(path: "package.json", name: "package.json", type: .json, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
        FileItem(path: "pnpm-lock.yaml", name: "pnpm-lock.yaml", type: .yaml, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
        FileItem(path: "pnpm-workspace.yaml", name: "pnpm-workspace.yaml", type: .yaml, isDirectory: false, childrenLoaded: true, hasChildrenHint: false),
        FileItem(path: "turbo.json", name: "turbo.json", type: .json, isDirectory: false, childrenLoaded: true, hasChildrenHint: false)
    ]

    // MARK: - Welcome Message

    static func welcomeMessage(for repoPath: String) -> String {
        "New chat in /\(repoPath)"
    }

    static let tipMessage = "Tip: O to open this session in your default app"
}
