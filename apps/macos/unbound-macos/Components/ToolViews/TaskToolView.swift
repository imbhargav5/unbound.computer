//
//  TaskToolView.swift
//  unbound-macos
//
//  Agent/task status display for Task tools
//

import SwiftUI

// MARK: - Task Tool View

/// Task/agent status display for Task, TaskCreate, TaskUpdate, TaskList, TaskGet tools
struct TaskToolView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    /// Get descriptive subtitle based on tool type
    private var subtitle: String {
        switch toolUse.toolName {
        case "Task":
            if let desc = parser.taskDescription {
                return desc
            }
            if let agentType = parser.subagentType {
                return "Agent: \(agentType)"
            }
            return "Running task"

        case "TaskCreate":
            if let subject = parser.string("subject") {
                return "Create: \(subject)"
            }
            return "Creating task"

        case "TaskUpdate":
            if let taskId = parser.string("taskId") {
                let status = parser.string("status") ?? ""
                return "Update #\(taskId)\(status.isEmpty ? "" : " → \(status)")"
            }
            return "Updating task"

        case "TaskList":
            return "Listing tasks"

        case "TaskGet":
            if let taskId = parser.string("taskId") {
                return "Getting task #\(taskId)"
            }
            return "Getting task"

        default:
            return parser.taskDescription ?? "Task operation"
        }
    }

    /// Icon based on tool type
    private var toolIcon: String {
        switch toolUse.toolName {
        case "Task": return "gearshape.2"
        case "TaskCreate": return "plus.circle"
        case "TaskUpdate": return "pencil.circle"
        case "TaskList": return "list.bullet"
        case "TaskGet": return "info.circle"
        default: return "checklist"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ToolHeader(
                toolName: toolUse.toolName,
                status: toolUse.status,
                subtitle: subtitle,
                icon: toolIcon,
                isExpanded: isExpanded,
                hasContent: toolUse.output != nil || parser.dictionary != nil,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ShadcnDivider()

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Input details
                        if let dict = parser.dictionary {
                            InputDetailsView(dictionary: dict)
                        }

                        // Output/Result
                        if let output = toolUse.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Result")
                                    .font(Typography.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(colors.mutedForeground)

                                ScrollView {
                                    Text(output)
                                        .font(Typography.code)
                                        .foregroundStyle(colors.foreground)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 150)
                                .padding(Spacing.sm)
                                .background(colors.muted)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }
}

// MARK: - Input Details View

struct InputDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let dictionary: [String: Any]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Filter and format important keys
    private var displayItems: [(key: String, value: String)] {
        let importantKeys = ["subject", "description", "taskId", "status", "subagent_type", "prompt"]
        return dictionary.compactMap { key, value in
            guard importantKeys.contains(key) else { return nil }
            let stringValue: String
            if let str = value as? String {
                stringValue = str
            } else if let bool = value as? Bool {
                stringValue = bool ? "true" : "false"
            } else if let num = value as? Int {
                stringValue = String(num)
            } else {
                stringValue = String(describing: value)
            }
            return (key: formatKey(key), value: stringValue)
        }
    }

    /// Format key for display
    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var body: some View {
        if !displayItems.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(displayItems, id: \.key) { item in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Text(item.key)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: 80, alignment: .trailing)

                        Text(item.value)
                            .font(Typography.body)
                            .foregroundStyle(colors.foreground)
                            .lineLimit(3)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG

#Preview {
    VStack(spacing: Spacing.md) {
        TaskToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Task",
            input: "{\"description\": \"Search codebase\", \"subagent_type\": \"Explore\", \"prompt\": \"Find all API endpoints\"}",
            output: "Found 5 API endpoints in src/routes/",
            status: .completed
        ))

        TaskToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "TaskCreate",
            input: "{\"subject\": \"Fix authentication bug\", \"description\": \"JWT tokens are expiring too early\"}",
            output: "Task #1 created successfully",
            status: .completed
        ))

        TaskToolView(toolUse: ToolUse(
            toolUseId: "test-3",
            toolName: "TaskUpdate",
            input: "{\"taskId\": \"1\", \"status\": \"completed\"}",
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}

#endif
