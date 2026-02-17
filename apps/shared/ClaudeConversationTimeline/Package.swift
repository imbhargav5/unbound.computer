// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeConversationTimeline",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClaudeConversationTimeline",
            targets: ["ClaudeConversationTimeline"]
        )
    ],
    targets: [
        .target(
            name: "ClaudeConversationTimeline",
            path: "Sources/ClaudeConversationTimeline"
        )
    ]
)
