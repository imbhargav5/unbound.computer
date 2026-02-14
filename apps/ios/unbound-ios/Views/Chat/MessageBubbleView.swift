import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    var showRoleIcon: Bool = true

    private var isUser: Bool { message.role == .user }
    private var timestampText: String { message.timestamp.formatted(date: .omitted, time: .shortened) }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppTheme.spacingS) {
            if isUser { Spacer(minLength: 60) }

            if !isUser && showRoleIcon {
                ClaudeAvatarView(size: 28)
                    .padding(.bottom, 4)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: AppTheme.spacingXS) {
                if isUser {
                    userTextBubble
                } else if let blocks = message.parsedContent, !blocks.isEmpty {
                    parsedContentView(blocks: blocks)
                } else {
                    assistantTextBubble
                }

                // Code blocks if present
                if let codeBlocks = message.codeBlocks {
                    ForEach(codeBlocks) { block in
                        CodeBlockView(codeBlock: block)
                    }
                }

                if !isUser {
                    timestampLabel
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    @ViewBuilder
    private func parsedContentView(blocks: [SessionContentBlock]) -> some View {
        let displayBlocks = groupedParsedBlocks(from: deduplicatedParsedBlocks(from: blocks))

        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            ForEach(displayBlocks) { displayBlock in
                switch displayBlock {
                case .standaloneToolUseGroup(let tools):
                    StandaloneToolCallsView(tools: tools)

                case .block(let block):
                    switch block {
                    case .text:
                        SessionContentBlockView(block: block)
                            .padding(.horizontal, AppTheme.spacingM)
                            .padding(.vertical, AppTheme.spacingS + 2)
                            .background(AppTheme.assistantBubble)
                            .clipShape(MessageBubbleShape(isUser: false))

                    case .toolUse, .subAgentActivity, .error:
                        SessionContentBlockView(block: block)
                    }
                }
            }
        }
    }

    private func groupedParsedBlocks(from blocks: [SessionContentBlock]) -> [ParsedDisplayBlock] {
        var grouped: [ParsedDisplayBlock] = []
        var pendingStandaloneTools: [SessionToolUse] = []

        func flushPendingTools() {
            guard !pendingStandaloneTools.isEmpty else { return }
            grouped.append(.standaloneToolUseGroup(pendingStandaloneTools))
            pendingStandaloneTools.removeAll(keepingCapacity: true)
        }

        for block in blocks {
            if case .toolUse(let tool) = block {
                pendingStandaloneTools.append(tool)
                continue
            }

            flushPendingTools()
            grouped.append(.block(block))
        }

        flushPendingTools()
        return grouped
    }

    private func deduplicatedParsedBlocks(from blocks: [SessionContentBlock]) -> [SessionContentBlock] {
        var seenStandaloneToolKeys: Set<String> = []
        var seenSubAgentParents: Set<String> = []
        var deduplicatedReversed: [SessionContentBlock] = []
        deduplicatedReversed.reserveCapacity(blocks.count)

        for block in blocks.reversed() {
            switch block {
            case .toolUse(let tool):
                let key = standaloneToolKey(for: tool)
                if seenStandaloneToolKeys.contains(key) {
                    continue
                }
                seenStandaloneToolKeys.insert(key)
                deduplicatedReversed.append(.toolUse(tool))

            case .subAgentActivity(let activity):
                if seenSubAgentParents.contains(activity.parentToolUseId) {
                    continue
                }
                seenSubAgentParents.insert(activity.parentToolUseId)

                let deduplicatedTools = deduplicatedToolsForSubAgent(activity.tools)
                let normalizedActivity = SessionSubAgentActivity(
                    id: activity.id,
                    parentToolUseId: activity.parentToolUseId,
                    subagentType: activity.subagentType,
                    description: activity.description,
                    tools: deduplicatedTools
                )
                deduplicatedReversed.append(.subAgentActivity(normalizedActivity))

            case .text, .error:
                deduplicatedReversed.append(block)
            }
        }

        return Array(deduplicatedReversed.reversed())
    }

    private func deduplicatedToolsForSubAgent(_ tools: [SessionToolUse]) -> [SessionToolUse] {
        var seenKeys: Set<String> = []
        var deduplicatedReversed: [SessionToolUse] = []
        deduplicatedReversed.reserveCapacity(tools.count)

        for tool in tools.reversed() {
            let key = standaloneToolKey(for: tool)
            if seenKeys.contains(key) {
                continue
            }
            seenKeys.insert(key)
            deduplicatedReversed.append(tool)
        }

        return Array(deduplicatedReversed.reversed())
    }

    private func standaloneToolKey(for tool: SessionToolUse) -> String {
        if let toolUseId = tool.toolUseId, !toolUseId.isEmpty {
            return "id:\(toolUseId)"
        }

        return "fallback:\(tool.parentToolUseId ?? "")|\(tool.toolName)|\(tool.summary)"
    }

    private var assistantTextBubble: some View {
        Text(message.content)
            .font(.body)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, AppTheme.spacingS + 2)
            .background(AppTheme.assistantBubble)
            .clipShape(MessageBubbleShape(isUser: false))
    }

    private var userTextBubble: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Text(message.content)
                .font(.body)
                .foregroundStyle(AppTheme.userBubbleText)

            Text(timestampText)
                .font(.caption2)
                .foregroundStyle(AppTheme.userBubbleTimestamp)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, AppTheme.spacingM)
        .padding(.vertical, AppTheme.spacingS + 2)
        .background(AppTheme.userBubbleBackground)
        .clipShape(MessageBubbleShape(isUser: true))
        .overlay(
            MessageBubbleShape(isUser: true)
                .stroke(AppTheme.userBubbleBorder, lineWidth: 1)
        )
    }

    private var timestampLabel: some View {
        Text(timestampText)
            .font(.caption2)
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, 4)
    }
}

private enum ParsedDisplayBlock: Identifiable {
    case block(SessionContentBlock)
    case standaloneToolUseGroup([SessionToolUse])

    var id: String {
        switch self {
        case .block(let block):
            return "block:\(block.id)"
        case .standaloneToolUseGroup(let tools):
            let ids = tools.map { $0.toolUseId ?? $0.id.uuidString }.joined(separator: ",")
            return "tool-group:\(ids)"
        }
    }
}

// MARK: - Message Bubble Shape

struct MessageBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let smallRadius: CGFloat = 4

        var path = Path()

        if isUser {
            // User bubble - rounded on all corners except bottom-right
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - smallRadius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - smallRadius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        } else {
            // Assistant bubble - rounded on all corners except bottom-left
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + smallRadius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - smallRadius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let codeBlock: Message.CodeBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let filename = codeBlock.filename {
                    Text(filename)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(codeBlock.language)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = codeBlock.code
                    let impactFeedback = UINotificationFeedbackGenerator()
                    impactFeedback.notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .background(Color.black.opacity(0.3))

            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(AppTheme.spacingS)
            }
        }
        .background(Color(white: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .frame(maxWidth: 320)
    }
}

#Preview("Message Bubbles") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(PreviewData.messages) { message in
                MessageBubbleView(message: message)
            }
        }
        .padding(.vertical)
    }
    .background(AppTheme.backgroundPrimary)
}

#Preview("Parsed Tool/SubAgent States") {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubbleView(
                message: Message(
                    content: "Parser-aligned block rendering",
                    role: .assistant,
                    parsedContent: [
                        .text("Working through parser state transitions."),
                        .toolUse(
                            SessionToolUse(
                                toolUseId: "tool-dup",
                                toolName: "Read",
                                summary: "Read README.md"
                            )
                        ),
                        .toolUse(
                            SessionToolUse(
                                toolUseId: "tool-dup",
                                toolName: "Read",
                                summary: "Read docs/README.md"
                            )
                        ),
                        .subAgentActivity(
                            SessionSubAgentActivity(
                                parentToolUseId: "task-1",
                                subagentType: "Explore",
                                description: "Investigate parser contract",
                                tools: [
                                    SessionToolUse(
                                        toolUseId: "task-tool-1",
                                        parentToolUseId: "task-1",
                                        toolName: "Grep",
                                        summary: "Grep raw_json"
                                    ),
                                    SessionToolUse(
                                        toolUseId: "task-tool-1",
                                        parentToolUseId: "task-1",
                                        toolName: "Grep",
                                        summary: "Grep raw_json"
                                    ),
                                ]
                            )
                        ),
                        .error("Tool execution failed with exit code 1"),
                    ]
                ),
                showRoleIcon: true
            )
        }
        .padding(.vertical)
    }
    .background(AppTheme.backgroundPrimary)
}
