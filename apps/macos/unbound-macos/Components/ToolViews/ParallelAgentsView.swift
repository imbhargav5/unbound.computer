//
//  ParallelAgentsView.swift
//  unbound-macos
//
//  Grouped parallel-agent rendering with design-matched summary header,
//  per-agent collapse, and compact expandable tool rows.
//

import Foundation
import SwiftUI

struct ParallelAgentsSummaryModel: Equatable {
    enum RingState: Equatable {
        case trackOnly
        case partial(Double)
        case complete
    }

    let title: String
    let ringState: RingState

    static func build(for agents: [ParallelAgentItem]) -> ParallelAgentsSummaryModel {
        let total = agents.count
        guard total > 0 else {
            return ParallelAgentsSummaryModel(title: "0 agents", ringState: .trackOnly)
        }

        let completed = agents.filter { $0.status == .completed }.count
        let running = agents.filter { $0.status == .running }.count
        let typeLabel = sharedTypeLabel(for: agents)
        let typeSegment = typeLabel.map { " \($0)" } ?? ""
        let noun = total == 1 ? "agent" : "agents"

        let title: String
        if completed == 0 && running > 0 {
            title = "Running \(total)\(typeSegment) \(noun)"
        } else if completed < total {
            title = "\(completed) of \(total)\(typeSegment) \(noun) finished"
        } else {
            title = "\(total)\(typeSegment) \(noun) finished"
        }

        let ringState: RingState
        if completed == 0 {
            ringState = .trackOnly
        } else if completed == total {
            ringState = .complete
        } else {
            ringState = .partial(Double(completed) / Double(total))
        }

        return ParallelAgentsSummaryModel(title: title, ringState: ringState)
    }

    private static func sharedTypeLabel(for agents: [ParallelAgentItem]) -> String? {
        let normalized = Set(agents.map { normalizeAgentType($0.subagentType) })
        guard normalized.count == 1, let value = normalized.first else {
            return nil
        }

        switch value {
        case "explore": return "Explore"
        case "plan": return "Plan"
        case "bash": return "Bash"
        case "general-purpose": return "General"
        default:
            if value.isEmpty { return nil }
            return value.prefix(1).uppercased() + value.dropFirst()
        }
    }

    private static func normalizeAgentType(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

struct ParallelAgentItem: Identifiable, Equatable {
    let id: String
    let subagentType: String
    let title: String
    let status: ToolStatus
    let tools: [ParallelToolItem]
    let result: String?
    let tokenSummary: String?

    var toolCountLabel: String {
        let noun = tools.count == 1 ? "tool use" : "tool uses"
        if let tokenSummary, !tokenSummary.isEmpty {
            return "· \(tools.count) \(noun) · \(tokenSummary)"
        }
        return "· \(tools.count) \(noun)"
    }

    init(activity: SubAgentActivity) {
        self.id = activity.parentToolUseId
        self.subagentType = activity.subagentType
        let trimmed = activity.description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? Self.fallbackTitle(for: activity.subagentType) : trimmed
        self.status = activity.status
        self.tools = activity.tools.map { ParallelToolItem(toolUse: $0) }
        self.result = activity.result
        self.tokenSummary = nil
    }

    init(activeSubAgent: ActiveSubAgent) {
        self.id = activeSubAgent.id
        self.subagentType = activeSubAgent.subagentType
        let trimmed = activeSubAgent.description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? Self.fallbackTitle(for: activeSubAgent.subagentType) : trimmed
        self.status = activeSubAgent.status
        self.tools = activeSubAgent.childTools.map { ParallelToolItem(activeTool: $0) }
        self.result = nil
        self.tokenSummary = nil
    }

    private static func fallbackTitle(for type: String) -> String {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "explore": return "Explore agent"
        case "plan": return "Plan agent"
        case "bash": return "Bash agent"
        case "general-purpose": return "General agent"
        default: return "\(type) agent"
        }
    }
}

struct ParallelToolItem: Identifiable, Equatable {
    let id: String
    let name: String
    let status: ToolStatus
    let preview: String?
    let input: String?
    let output: String?

    var hasDetails: Bool {
        let inputHasValue = input?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let outputHasValue = output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return inputHasValue || outputHasValue
    }

    init(toolUse: ToolUse) {
        self.id = toolUse.toolUseId ?? UUID().uuidString
        self.name = toolUse.toolName
        self.status = toolUse.status
        self.preview = Self.previewText(fromInput: toolUse.input, fallback: nil)
        self.input = toolUse.input
        self.output = toolUse.output
    }

    init(activeTool: ActiveTool) {
        self.id = activeTool.id
        self.name = activeTool.name
        self.status = activeTool.status
        self.preview = activeTool.inputPreview
        self.input = activeTool.inputPreview
        self.output = activeTool.output
    }

    private static func previewText(fromInput input: String?, fallback: String?) -> String? {
        let parser = ToolInputParser(input)
        if let preview = parser.filePath ?? parser.pattern ?? parser.commandDescription ?? parser.command ?? parser.query ?? parser.url {
            return preview
        }
        return fallback
    }
}

struct ParallelAgentsView: View {
    private let agents: [ParallelAgentItem]
    private let defaultExpanded: Bool
    private let outerPadding: EdgeInsets
    private static let defaultOuterPadding = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

    init(
        activities: [SubAgentActivity],
        defaultExpanded: Bool = false,
        outerPadding: EdgeInsets = Self.defaultOuterPadding
    ) {
        self.agents = activities.map(ParallelAgentItem.init(activity:))
        self.defaultExpanded = defaultExpanded
        self.outerPadding = outerPadding
    }

    init(
        activeSubAgents: [ActiveSubAgent],
        defaultExpanded: Bool = false,
        outerPadding: EdgeInsets = Self.defaultOuterPadding
    ) {
        self.agents = activeSubAgents.map(ParallelAgentItem.init(activeSubAgent:))
        self.defaultExpanded = defaultExpanded
        self.outerPadding = outerPadding
    }

    @State private var expandedAgentIDs: Set<String> = []

    private var summaryModel: ParallelAgentsSummaryModel {
        ParallelAgentsSummaryModel.build(for: agents)
    }

    var body: some View {
        if !agents.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                summaryHeader

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                        ParallelAgentRowView(
                            agent: agent,
                            isExpanded: expandedAgentIDs.contains(agent.id),
                            isLast: index == agents.count - 1,
                            defaultExpanded: defaultExpanded,
                            onToggle: { toggle(agentID: agent.id) }
                        )
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
            }
            .background(Color(hex: "1A1A1A"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "2A2A2A"), lineWidth: BorderWidth.default)
            )
            .padding(outerPadding)
        }
    }

    private var summaryHeader: some View {
        HStack(alignment: .center) {
            Text(summaryModel.title)
                .font(GeistFont.sans(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "E5E5E5"))

            Spacer()

            ParallelProgressRing(state: summaryModel.ringState)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func toggle(agentID: String) {
        withAnimation(.easeInOut(duration: Duration.fast)) {
            if expandedAgentIDs.contains(agentID) {
                expandedAgentIDs.remove(agentID)
            } else {
                expandedAgentIDs.insert(agentID)
            }
        }
    }
}

private struct ParallelProgressRing: View {
    let state: ParallelAgentsSummaryModel.RingState

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "2A2A2A"), lineWidth: 2)

            switch state {
            case .trackOnly:
                EmptyView()
            case .partial(let progress):
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(Color(hex: "F59E0B"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            case .complete:
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(Color(hex: "3FB950"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 20, height: 20)
    }
}

private struct ParallelAgentRowView: View {
    let agent: ParallelAgentItem
    let isExpanded: Bool
    let isLast: Bool
    let defaultExpanded: Bool
    let onToggle: () -> Void

    @State private var didInitialize = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TreeConnector(isLast: isLast)

            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    HStack(alignment: .center, spacing: 6) {
                        HStack(alignment: .center, spacing: 6) {
                            statusIcon

                            Text(agent.title)
                                .font(GeistFont.mono(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "B3B3B3"))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(agent.toolCountLabel)
                                .font(GeistFont.mono(size: 11, weight: .regular))
                                .foregroundStyle(Color(hex: "6B6B6B"))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: "6B6B6B"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    if !agent.tools.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(agent.tools) { tool in
                                ParallelAgentToolRowView(tool: tool)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }

                    if let result = agent.result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty {
                        Text(result)
                            .font(GeistFont.sans(size: 11, weight: .regular))
                            .lineSpacing(3)
                            .foregroundStyle(Color(hex: "B3B3B3"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                    }
                }
            }
            .background(Color(hex: "111111"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(hex: "2A2A2A"), lineWidth: BorderWidth.default)
            )
        }
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            if defaultExpanded {
                onToggle()
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch agent.status {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(Color(hex: "F59E0B"))
                .scaleEffect(0.55)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "3FB950"))
                .frame(width: 14, height: 14)
        case .failed:
            Image(systemName: "xmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "F87149"))
                .frame(width: 14, height: 14)
        }
    }
}

private struct TreeConnector: View {
    let isLast: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(hex: "2A2A2A"))
                .frame(width: 1)
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(isLast ? 0 : 1)

            Rectangle()
                .fill(Color(hex: "2A2A2A"))
                .frame(width: 12, height: 1)
                .offset(y: 18)

            if isLast {
                Rectangle()
                    .fill(Color(hex: "2A2A2A"))
                    .frame(width: 1, height: 19)
            }
        }
        .frame(width: 20)
    }
}

private struct ParallelAgentToolRowView: View {
    let tool: ParallelToolItem

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tool.hasDetails {
                Button {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
            } else {
                header
            }

            if isExpanded && tool.hasDetails {
                VStack(alignment: .leading, spacing: 8) {
                    if let input = tool.input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
                        detailSection(title: "Input", text: input)
                    }

                    if let output = tool.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                        detailSection(title: "Output", text: output)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "2A2A2A"))
                        .frame(height: 1)
                }
            }
        }
        .background(Color(hex: "0D0D0D"))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(hex: "2A2A2A"), lineWidth: BorderWidth.default)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            statusIcon

            Text(tool.name)
                .font(GeistFont.mono(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "B3B3B3"))

            if let preview = tool.preview, !preview.isEmpty {
                Text(preview)
                    .font(GeistFont.mono(size: 10, weight: .regular))
                    .foregroundStyle(Color(hex: "6B6B6B"))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if tool.hasDetails {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(hex: "6B6B6B"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tool.status {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(Color(hex: "F59E0B"))
                .scaleEffect(0.5)
                .frame(width: 8, height: 8)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 8, height: 8)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(hex: "F87149"))
                .frame(width: 8, height: 8)
        }
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(GeistFont.sans(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: "8A8A8A"))

            ScrollView {
                Text(text)
                    .font(GeistFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "B3B3B3"))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
    }
}

#if DEBUG

#Preview("Parallel Agents - Historical") {
    VStack {
        ParallelAgentsView(activities: [
            SubAgentActivity(
                parentToolUseId: "task-1",
                subagentType: "Explore",
                description: "Explore daemon crate structure",
                tools: [
                    ToolUse(toolUseId: "tool-1", parentToolUseId: "task-1", toolName: "Read", input: "{\"file_path\":\"src/daemon/mod.rs\"}", status: .completed),
                    ToolUse(toolUseId: "tool-2", parentToolUseId: "task-1", toolName: "Grep", input: "{\"pattern\":\"pub fn\"}", status: .completed),
                    ToolUse(toolUseId: "tool-3", parentToolUseId: "task-1", toolName: "Read", input: "{\"file_path\":\"src/daemon/process.rs\"}", status: .completed),
                ],
                status: .completed,
                result: "Mapped daemon crate structure: 4 modules, 12 public functions across process, config, and IPC layers."
            ),
            SubAgentActivity(
                parentToolUseId: "task-2",
                subagentType: "Explore",
                description: "Count existing tests per crate",
                tools: [
                    ToolUse(toolUseId: "tool-4", parentToolUseId: "task-2", toolName: "Glob", input: "{\"pattern\":\"**/*_test.rs\"}", status: .running),
                ],
                status: .running
            ),
        ])
        .padding(16)
        .background(Color(hex: "0F0F0F"))
    }
    .frame(width: 620)
}

#endif
