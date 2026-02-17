// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionsApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SessionsApp",
            targets: ["SessionsApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.5.0"),
        .package(path: "../shared/ClaudeConversationTimeline")
    ],
    targets: [
        .target(
            name: "SessionsApp",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "ClaudeConversationTimeline", package: "ClaudeConversationTimeline")
            ],
            path: "Sources"
        )
    ]
)
