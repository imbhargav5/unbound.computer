//
//  ToolViewRouter.swift
//  unbound-macos
//
//  Routes tool use blocks to specialized views based on tool name
//

import SwiftUI
import Logging

private let logger = Logger(label: "app.ui")

// MARK: - Tool View Router

/// Routes to specialized views based on toolUse.toolName
struct ToolViewRouter: View {
    let toolUse: ToolUse

    var body: some View {
        ToolUseView(toolUse: toolUse)
    }
}

// MARK: - Preview

#if DEBUG

#Preview {
    VStack(spacing: Spacing.md) {
        ToolViewRouter(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Bash",
            input: "{\"command\": \"npm test\", \"description\": \"Run test suite\"}",
            output: "PASS  src/test.ts\n  Test Suite\n    ✓ should pass (5ms)",
            status: .completed
        ))

        ToolViewRouter(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Read",
            input: "{\"file_path\": \"/src/main.swift\"}",
            output: "import Foundation\n\nfunc main() {\n    print(\"Hello\")\n}",
            status: .completed
        ))

        ToolViewRouter(toolUse: ToolUse(
            toolUseId: "test-3",
            toolName: "CustomTool",
            input: "{\"key\": \"value\"}",
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}

#endif
