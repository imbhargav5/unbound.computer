// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MobileClaudeCodeConversationTimeline",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MobileClaudeCodeConversationTimeline",
            targets: ["MobileClaudeCodeConversationTimeline"]
        )
    ],
    targets: [
        .target(
            name: "MobileClaudeCodeConversationTimeline",
            path: "Sources/MobileClaudeCodeConversationTimeline"
        )
    ]
)
