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

    // MARK: - Welcome Message

    static func welcomeMessage(for repoPath: String) -> String {
        "New chat in /\(repoPath)"
    }

    static let tipMessage = "Tip: O to open this session in your default app"
}
