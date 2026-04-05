//
//  SubAgentView.swift
//  unbound-macos
//
//  Card-based sub-agent rendering that mirrors timeline design nodes.
//

import Foundation
import SwiftUI

private enum SubAgentPayload {
    case active(ActiveSubAgent)
    case historical(SubAgentActivity)
}

struct SubAgentView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let payload: SubAgentPayload
    @State private var isExpanded: Bool

    init(activeSubAgent: ActiveSubAgent, initiallyExpanded: Bool = true) {
        self.payload = .active(activeSubAgent)
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    init(activity: SubAgentActivity, initiallyExpanded: Bool = false) {
        self.payload = .historical(activity)
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var subagentType: String {
        switch payload {
        case .active(let subAgent):
            return subAgent.subagentType
        case .historical(let activity):
            return activity.subagentType
        }
    }

    private var descriptionText: String {
        switch payload {
        case .active(let subAgent):
            return subAgent.description
        case .historical(let activity):
            return activity.description
        }
    }

    private var tools: [ToolUse] {
        switch payload {
        case .active(let subAgent):
            return subAgent.childTools.map {
                ToolUse(
                    toolUseId: $0.id,
                    parentToolUseId: subAgent.id,
                    toolName: $0.name,
                    input: normalizedInput(for: $0),
                    output: $0.output,
                    status: $0.status
                )
            }
        case .historical(let activity):
            return activity.tools
        }
    }

    private var status: ToolStatus {
        switch payload {
        case .active(let subAgent):
            return subAgent.status
        case .historical(let activity):
            return activity.status
        }
    }

    private var cardBorderColor: Color {
        switch status {
        case .failed:
            return Color(hex: "F8714930")
        case .running, .completed:
            return Color(hex: "2A2A2A")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded && !tools.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                        NestedToolRow(
                            tool: tool,
                            isLast: index == tools.count - 1
                        )
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 24)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "2A2A2A"))
                        .frame(height: 1)
                }
            }
        }
        .background(Color(hex: "1A1A1A"))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(cardBorderColor, lineWidth: BorderWidth.default)
        )
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: agentIcon(for: subagentType))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.mutedForeground)
                    .frame(width: 18, height: 18)

                Text(agentDisplayName(for: subagentType))
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.foreground)

                if !descriptionText.isEmpty {
                    Text("·")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)

                    Text(descriptionText)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()

                statusBadge

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: IconSize.xs))
                    .foregroundStyle(colors.mutedForeground)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .running:
            Text("Running")
                .font(Typography.caption)
                .foregroundStyle(Color(hex: "F59E0B"))
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(colors.success)
        case .failed:
            Text("Failed")
                .font(Typography.caption)
                .foregroundStyle(Color(hex: "F87149"))
        }
    }

    private func agentDisplayName(for type: String) -> String {
        switch type.lowercased() {
        case "explore":
            return "Explore Agent"
        case "plan":
            return "Plan Agent"
        case "bash":
            return "Bash Agent"
        case "general-purpose":
            return "General Agent"
        default:
            return "\(type) Agent"
        }
    }

    private func agentIcon(for type: String) -> String {
        switch type.lowercased() {
        case "explore":
            return "binoculars.fill"
        case "plan":
            return "list.bullet.clipboard.fill"
        case "bash":
            return "terminal.fill"
        default:
            return "cpu.fill"
        }
    }

    private func normalizedInput(for tool: ActiveTool) -> String? {
        guard let preview = tool.inputPreview, !preview.isEmpty else { return nil }
        let key: String = switch tool.name {
        case "Read", "Write", "Edit": "file_path"
        case "Bash": "command"
        case "Glob", "Grep": "pattern"
        case "WebSearch": "query"
        case "WebFetch": "url"
        default: "description"
        }
        let payload = [key: preview]
        return (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) }
    }
}

private struct NestedToolRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let tool: ToolUse
    let isLast: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var previewText: String? {
        let parser = ToolInputParser(tool.input)
        return parser.filePath ?? parser.pattern ?? parser.command ?? parser.query ?? parser.url
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Image(systemName: ToolIcon.icon(for: tool.toolName))
                .font(.system(size: 10))
                .foregroundStyle(colors.mutedForeground)
                .frame(width: 14, height: 14)

            Text(tool.toolName)
                .font(Typography.code)
                .foregroundStyle(colors.foreground)

            if let previewText, !previewText.isEmpty {
                Text(previewText)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            statusIcon
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(hex: "2A2A2A"))
                .frame(width: 1)
                .offset(x: -10)
                .opacity(isLast ? 0 : 1)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tool.status {
        case .running:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: "3FB950"))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: "F87149"))
        }
    }
}
