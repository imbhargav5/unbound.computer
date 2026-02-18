//
//  ParallelAgentsView.swift
//  unbound-ios
//
//  Grouped parallel-agent renderer matching desktop design states.
//

import SwiftUI

struct ParallelAgentsView: View {
    let activities: [SessionSubAgentActivity]
    var defaultRowExpanded: Bool = false

    @State private var expandedAgentIDs: Set<String> = []

    private var summary: ParallelAgentsSummary {
        ParallelAgentsSummary.build(for: activities)
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                summaryHeader

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activities.enumerated()), id: \.element.parentToolUseId) { index, activity in
                        ParallelAgentRow(
                            activity: activity,
                            isLast: index == activities.count - 1,
                            isExpanded: expandedAgentIDs.contains(activity.parentToolUseId),
                            defaultExpanded: defaultRowExpanded,
                            onToggle: { toggle(activity.parentToolUseId) }
                        )
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
            }
            .padding(16)
            .background(hexColor("0F0F0F"))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(hexColor("2A2A2A"), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var summaryHeader: some View {
        HStack(alignment: .center) {
            Text(summary.title)
                .font(GeistFont.sans(size: 13, weight: .semibold))
                .foregroundStyle(hexColor("E5E5E5"))

            Spacer(minLength: 8)

            ParallelProgressRing(state: summary.ringState)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(hexColor("1A1A1A"))
    }

    private func toggle(_ agentID: String) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if expandedAgentIDs.contains(agentID) {
                expandedAgentIDs.remove(agentID)
            } else {
                expandedAgentIDs.insert(agentID)
            }
        }
    }
}

private struct ParallelAgentRow: View {
    let activity: SessionSubAgentActivity
    let isLast: Bool
    let isExpanded: Bool
    let defaultExpanded: Bool
    let onToggle: () -> Void

    @State private var initialized = false

    private var rowTitle: String {
        let trimmed = activity.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return activity.displayName
    }

    private var metaText: String {
        let noun = activity.tools.count == 1 ? "tool use" : "tool uses"
        return "· \(activity.tools.count) \(noun)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TreeConnector(isLast: isLast)

            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        statusIcon

                        Text(rowTitle)
                            .font(GeistFont.mono(size: 12, weight: .medium))
                            .foregroundStyle(hexColor("B3B3B3"))
                            .lineLimit(1)

                        Text(metaText)
                            .font(GeistFont.mono(size: 11, weight: .regular))
                            .foregroundStyle(hexColor("6B6B6B"))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(hexColor("6B6B6B"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(activity.tools) { tool in
                            ParallelToolRow(tool: tool)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)

                    if let result = activity.result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty {
                        Text(result)
                            .font(GeistFont.sans(size: 11, weight: .regular))
                            .foregroundStyle(hexColor("B3B3B3"))
                            .lineSpacing(3)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(hexColor("111111"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hexColor("2A2A2A"), lineWidth: 1)
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if defaultExpanded {
                onToggle()
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch activity.status {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(hexColor("F59E0B"))
                .scaleEffect(0.55)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hexColor("3FB950"))
                .frame(width: 14, height: 14)
        case .failed:
            Image(systemName: "xmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hexColor("F87149"))
                .frame(width: 14, height: 14)
        }
    }
}

private struct ParallelToolRow: View {
    let tool: SessionToolUse

    @State private var isExpanded = false

    private var hasDetails: Bool {
        let hasInput = tool.input?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasOutput = tool.output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasInput || hasOutput
    }

    private var previewText: String? {
        if let parsed = toolPreviewFromInput(tool.input) {
            return parsed
        }

        if tool.summary.hasPrefix("\(tool.toolName) ") {
            return String(tool.summary.dropFirst(tool.toolName.count + 1))
        }

        return tool.summary == tool.toolName ? nil : tool.summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasDetails {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isExpanded.toggle()
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
            } else {
                header
            }

            if isExpanded && hasDetails {
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
                        .fill(hexColor("2A2A2A"))
                        .frame(height: 1)
                }
            }
        }
        .background(hexColor("0D0D0D"))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(hexColor("2A2A2A"), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            statusIcon

            Text(tool.toolName)
                .font(GeistFont.mono(size: 11, weight: .medium))
                .foregroundStyle(hexColor("B3B3B3"))

            if let previewText, !previewText.isEmpty {
                Text(previewText)
                    .font(GeistFont.mono(size: 10, weight: .regular))
                    .foregroundStyle(hexColor("6B6B6B"))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if hasDetails {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(hexColor("6B6B6B"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(GeistFont.sans(size: 10, weight: .medium))
                .foregroundStyle(hexColor("8A8A8A"))

            ScrollView {
                Text(text)
                    .font(GeistFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(hexColor("B3B3B3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tool.status {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(hexColor("F59E0B"))
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
                .foregroundStyle(hexColor("F87149"))
                .frame(width: 8, height: 8)
        }
    }
}

private struct TreeConnector: View {
    let isLast: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(hexColor("2A2A2A"))
                .frame(width: 1)
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(isLast ? 0 : 1)

            Rectangle()
                .fill(hexColor("2A2A2A"))
                .frame(width: 12, height: 1)
                .offset(y: 18)

            if isLast {
                Rectangle()
                    .fill(hexColor("2A2A2A"))
                    .frame(width: 1, height: 19)
            }
        }
        .frame(width: 20)
    }
}

private struct ParallelProgressRing: View {
    let state: ParallelAgentsSummary.RingState

    var body: some View {
        ZStack {
            Circle()
                .stroke(hexColor("2A2A2A"), lineWidth: 2)

            switch state {
            case .trackOnly:
                EmptyView()
            case .partial(let progress):
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(hexColor("F59E0B"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            case .complete:
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(hexColor("3FB950"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 20, height: 20)
    }
}

private struct ParallelAgentsSummary {
    enum RingState {
        case trackOnly
        case partial(Double)
        case complete
    }

    let title: String
    let ringState: RingState

    static func build(for activities: [SessionSubAgentActivity]) -> ParallelAgentsSummary {
        let total = activities.count
        guard total > 0 else {
            return ParallelAgentsSummary(title: "0 agents", ringState: .trackOnly)
        }

        let completed = activities.filter { $0.status == .completed }.count
        let running = activities.filter { $0.status == .running }.count
        let typeLabel = sharedTypeLabel(for: activities)
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

        return ParallelAgentsSummary(title: title, ringState: ringState)
    }

    private static func sharedTypeLabel(for activities: [SessionSubAgentActivity]) -> String? {
        let types = Set(activities.map {
            $0.subagentType
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
        })

        guard types.count == 1, let type = types.first else {
            return nil
        }

        switch type {
        case "explore": return "Explore"
        case "plan": return "Plan"
        case "bash": return "Bash"
        case "general-purpose": return "General"
        default:
            guard !type.isEmpty else { return nil }
            return type.prefix(1).uppercased() + type.dropFirst()
        }
    }
}

private func toolPreviewFromInput(_ input: String?) -> String? {
    guard let input,
          let data = input.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    return json["file_path"] as? String
        ?? json["pattern"] as? String
        ?? json["description"] as? String
        ?? json["command"] as? String
        ?? json["query"] as? String
        ?? json["url"] as? String
}

private func hexColor(_ hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var intValue: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&intValue)

    let red, green, blue: UInt64
    switch cleaned.count {
    case 3:
        (red, green, blue) = (
            ((intValue >> 8) & 0xF) * 17,
            ((intValue >> 4) & 0xF) * 17,
            (intValue & 0xF) * 17
        )
    default:
        (red, green, blue) = (
            (intValue >> 16) & 0xFF,
            (intValue >> 8) & 0xFF,
            intValue & 0xFF
        )
    }

    return Color(
        .sRGB,
        red: Double(red) / 255,
        green: Double(green) / 255,
        blue: Double(blue) / 255,
        opacity: 1
    )
}

#Preview("Parallel Agents") {
    ParallelAgentsView(
        activities: [
            SessionSubAgentActivity(
                parentToolUseId: "task-1",
                subagentType: "Explore",
                description: "Explore daemon crate structure",
                tools: [
                    SessionToolUse(toolUseId: "t1", parentToolUseId: "task-1", toolName: "Read", summary: "Read src/daemon/mod.rs", status: .completed, input: "{\"file_path\":\"src/daemon/mod.rs\"}"),
                    SessionToolUse(toolUseId: "t2", parentToolUseId: "task-1", toolName: "Grep", summary: "Grep pattern: pub fn", status: .completed, input: "{\"pattern\":\"pub fn\"}"),
                    SessionToolUse(toolUseId: "t3", parentToolUseId: "task-1", toolName: "Read", summary: "Read src/daemon/process.rs", status: .completed, input: "{\"file_path\":\"src/daemon/process.rs\"}"),
                ],
                status: .completed,
                result: "Mapped daemon crate structure: 4 modules, 12 public functions across process, config, and IPC layers."
            ),
            SessionSubAgentActivity(
                parentToolUseId: "task-2",
                subagentType: "Explore",
                description: "Count existing tests per crate",
                tools: [
                    SessionToolUse(toolUseId: "t4", parentToolUseId: "task-2", toolName: "Glob", summary: "Glob **/*_test.rs", status: .running, input: "{\"pattern\":\"**/*_test.rs\"}")
                ],
                status: .running
            ),
        ]
    )
    .padding()
    .background(hexColor("0A0A0A"))
}
