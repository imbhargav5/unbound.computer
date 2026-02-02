//
//  ChatComponents.swift
//  unbound-macos
//
//  Shadcn-styled chat components
//

import SwiftUI
import AppKit
import Logging

private let logger = Logger(label: "app.ui.chat")

// MARK: - Command Return Text Editor

/// Custom NSTextView that intercepts Cmd+Return and Shift+Tab
private class CommandReturnNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    var onShiftTab: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Check for Cmd+Return (keyCode 36 is Return)
        if event.keyCode == 36 && event.modifierFlags.contains(.command) {
            onCommandReturn?()
            return
        }
        // Check for Shift+Tab (keyCode 48 is Tab)
        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            onShiftTab?()
            return
        }
        super.keyDown(with: event)
    }
}

/// A TextEditor wrapper that intercepts Cmd+Return and Shift+Tab
struct CommandReturnTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onCommandReturn: () -> Void
    var onShiftTab: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CommandReturnNSTextView()
        textView.onCommandReturn = onCommandReturn
        textView.onShiftTab = onShiftTab
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CommandReturnNSTextView else { return }

        // Only update if text actually changed to avoid cursor jumping
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        textView.onCommandReturn = onCommandReturn
        textView.onShiftTab = onShiftTab
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

// MARK: - Chat Input Field

struct ChatInputField: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    @Binding var selectedModel: AIModel
    @Binding var selectedThinkMode: ThinkMode
    @Binding var isPlanMode: Bool
    var isStreaming: Bool = false
    var onSend: () -> Void
    var onCancel: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Plan mode indicator
            if isPlanMode {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "map")
                        .font(.system(size: IconSize.sm))
                    Text("Plan Mode")
                        .font(Typography.caption)
                        .fontWeight(.medium)
                    Text("⇧⇥ to toggle")
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)
                    Spacer()
                }
                .foregroundStyle(colors.info)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)
            }

            // Text input area
            CommandReturnTextEditor(
                text: $text,
                onCommandReturn: {
                    if !isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                },
                onShiftTab: {
                    isPlanMode.toggle()
                }
            )
                .font(Typography.body)
                .focused($isFocused)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(.horizontal, Spacing.md)
                .padding(.top, isPlanMode ? Spacing.xs : Spacing.md)

            // Bottom toolbar
            HStack {
                // Left group: Model and think mode selector
                HStack(spacing: Spacing.sm) {
                    ModelSelector(selectedModel: $selectedModel, selectedThinkMode: $selectedThinkMode)
                }
                .fixedSize()

                Spacer()

                // Right group: Send/Stop button
                HStack(spacing: Spacing.sm) {
                    if isStreaming {
                        Button(action: { onCancel?() }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: IconSize.xxl))
                                .foregroundStyle(colors.destructive)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onSend) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: IconSize.xxl))
                                .foregroundStyle(text.isEmpty ? colors.mutedForeground : colors.primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(text.isEmpty)
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
        .background(isPlanMode ? colors.info.opacity(0.05) : colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(isPlanMode ? colors.info : (isFocused ? colors.ring : colors.border), lineWidth: isPlanMode ? BorderWidth.thick : BorderWidth.default)
        )
        .animation(.easeInOut(duration: Duration.fast), value: isFocused)
        .animation(.easeInOut(duration: Duration.fast), value: isPlanMode)
    }
}

// MARK: - Model Selector

struct ModelSelector: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedModel: AIModel
    @Binding var selectedThinkMode: ThinkMode

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Model dropdown
            Menu {
                ForEach(AIModel.allModels) { model in
                    Button {
                        selectedModel = model
                        // Reset think mode if model doesn't support it
                        if !model.supportsThinking && selectedThinkMode != .none {
                            selectedThinkMode = .none
                        }
                    } label: {
                        Label(model.name, systemImage: model.iconName)
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: selectedModel.iconName)
                        .font(.system(size: IconSize.sm))
                    Text(selectedModel.name)
                        .font(Typography.bodySmall)
                    Image(systemName: "chevron.down")
                        .font(.system(size: IconSize.xs))
                }
                .foregroundStyle(colors.mutedForeground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .background(colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .menuStyle(.borderlessButton)

            // Think mode dropdown (only show if model supports thinking)
            if selectedModel.supportsThinking {
                Menu {
                    ForEach(ThinkMode.allCases) { mode in
                        Button {
                            selectedThinkMode = mode
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(mode.name)
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: mode.iconName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: selectedThinkMode.iconName)
                            .font(.system(size: IconSize.sm))
                        Text(selectedThinkMode.name)
                            .font(Typography.bodySmall)
                        Image(systemName: "chevron.down")
                            .font(.system(size: IconSize.xs))
                    }
                    .foregroundStyle(selectedThinkMode == .none ? colors.mutedForeground : colors.info)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(selectedThinkMode == .none ? colors.muted : colors.info.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .menuStyle(.borderlessButton)
            }
        }
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: ChatMessage
    var index: Int = 0  // For stagger animation
    var onQuestionSubmit: ((AskUserQuestion) -> Void)?

    @State private var isHovered = false
    @State private var hasAppeared = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Stagger delay based on index
    private var staggerDelay: Double {
        Double(index) * Duration.staggerInterval
    }

    /// Get deduplicated content for display - tools with the same toolUseId show only the latest state
    /// This preserves stream order in storage/relay while preventing duplicate tool UI
    /// Also fixes "stuck running" tools in non-streaming messages (legacy data)
    private var displayContent: [MessageContent] {
        var seenToolUseIds: Set<String> = []
        var result: [MessageContent] = []

        // Process in reverse to find the latest state of each tool first
        for content in message.content.reversed() {
            if case .toolUse(var toolUse) = content,
               let toolUseId = toolUse.toolUseId {
                // Only include the first occurrence (which is the latest due to reverse)
                if seenToolUseIds.contains(toolUseId) {
                    continue
                }
                seenToolUseIds.insert(toolUseId)

                // Fix legacy data: if message is not streaming but tool shows "running", mark as completed
                if !message.isStreaming && toolUse.status == .running {
                    toolUse.status = .completed
                    result.append(.toolUse(toolUse))
                    continue
                }
            } else if case .subAgentActivity(var subAgent) = content {
                // Track sub-agent's parent tool ID
                if seenToolUseIds.contains(subAgent.parentToolUseId) {
                    continue
                }
                seenToolUseIds.insert(subAgent.parentToolUseId)

                // Fix legacy data: if message is not streaming but sub-agent shows "running", mark as completed
                if !message.isStreaming && subAgent.status == .running {
                    subAgent.status = .completed
                    // Also mark all child tools as completed
                    for i in 0..<subAgent.tools.count where subAgent.tools[i].status == .running {
                        subAgent.tools[i].status = .completed
                    }
                    result.append(.subAgentActivity(subAgent))
                    continue
                }
            }
            result.append(content)
        }

        // Reverse back to original order
        let finalResult = Array(result.reversed())
        return finalResult
    }

    /// Get all copyable text from the message
    private var copyableText: String {
        displayContent.compactMap { content in
            switch content {
            case .text(let textContent):
                return textContent.text
            case .codeBlock(let codeBlock):
                return "```\(codeBlock.language ?? "")\n\(codeBlock.code)\n```"
            case .error(let error):
                return "Error: \(error.message)\(error.details.map { "\n\($0)" } ?? "")"
            case .todoList(let todoList):
                return todoList.items.map { "- [\($0.status == .completed ? "x" : " ")] \($0.content)" }.joined(separator: "\n")
            case .fileChange(let fileChange):
                return "\(fileChange.changeType.rawValue): \(fileChange.filePath)"
            case .toolUse(let toolUse):
                return "Tool: \(toolUse.toolName)"
            case .subAgentActivity(let activity):
                let toolNames = activity.tools.map { $0.toolName }.joined(separator: ", ")
                return "Sub-Agent (\(activity.subagentType)): \(activity.description)\nTools: \(toolNames)\(activity.result.map { "\nResult: \($0)" } ?? "")"
            case .askUserQuestion(let question):
                return question.question
            case .eventPayload(let payload):
                return "Event: \(payload.eventType)"
            }
        }.joined(separator: "\n\n")
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copyableText, forType: .string)
    }

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if isUser {
                Spacer(minLength: 60)
            }

            // Content
            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.sm) {
                // Streaming indicator for assistant
                if !isUser && message.isStreaming {
                    TypingDotsIndicator()
                }

                // Render content blocks (deduplicated for display)
                ForEach(displayContent) { content in
                    MessageContentView(
                        content: content,
                        onQuestionSubmit: onQuestionSubmit
                    )
                }

                // Action row (copy button on hover)
                if isHovered && !message.isStreaming {
                    HStack(spacing: Spacing.sm) {
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: IconSize.xs))
                                .foregroundStyle(colors.mutedForeground)
                        }
                        .buttonStyle(.plain)
                        .help("Copy message")
                    }
                }
            }
            .padding(isUser ? Spacing.md : 0)
            .background(
                Group {
                    if isUser {
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .fill(colors.muted)
                    }
                }
            )

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Copy") {
                copyToClipboard()
            }
        }
        .slideIn(isVisible: hasAppeared, from: .bottom, delay: staggerDelay)
        .onAppear {
            // Small delay to ensure the view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Message Content View

struct MessageContentView: View {
    let content: MessageContent
    var onQuestionSubmit: ((AskUserQuestion) -> Void)?

    init(content: MessageContent, onQuestionSubmit: ((AskUserQuestion) -> Void)? = nil) {
        self.content = content
        self.onQuestionSubmit = onQuestionSubmit
    }

    var body: some View {
        switch content {
        case .text(let textContent):
            TextContentView(textContent: textContent)

        case .codeBlock(let codeBlock):
            CodeBlockView(codeBlock: codeBlock)

        case .askUserQuestion(let question):
            if let onSubmit = onQuestionSubmit {
                AskUserQuestionView(question: question, onSubmit: onSubmit)
            }

        case .todoList(let todoList):
            TodoListView(todoList: todoList)

        case .fileChange(let fileChange):
            FileChangeView(fileChange: fileChange)

        case .toolUse(let toolUse):
            ToolViewRouter(toolUse: toolUse)

        case .subAgentActivity(let activity):
            SubAgentActivityView(activity: activity)

        case .error(let error):
            ErrorContentView(error: error)

        case .eventPayload:
            // Event payloads are internal relay events, not displayed in UI
            EmptyView()
        }
    }
}

// MARK: - Text Content View

struct TextContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    let textContent: TextContent

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Protocol JSON patterns that should never be displayed to users
    private static let protocolPatterns = [
        "{\"type\":\"user\"",
        "{\"type\":\"system\"",
        "{\"type\":\"assistant\"",
        "{\"type\":\"result\""
    ]

    /// Extract text from JSON result if present, strip protocol JSON
    private var displayText: String {
        var text = textContent.text

        // Strip ALL protocol JSON patterns
        for pattern in Self.protocolPatterns {
            text = stripProtocolJSON(from: text, pattern: pattern)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip protocol JSON from text, extracting result field if applicable
    private func stripProtocolJSON(from text: String, pattern: String) -> String {
        guard let startRange = text.range(of: pattern) else { return text }

        var braceCount = 0
        var endIndex: String.Index?

        for index in text[startRange.lowerBound...].indices {
            let char = text[index]
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    endIndex = text.index(after: index)
                    break
                }
            }
        }

        guard let end = endIndex else { return text }

        // For result type, extract the actual result field
        if pattern == "{\"type\":\"result\"" {
            let jsonString = String(text[startRange.lowerBound..<end])
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String {
                var modified = text
                modified.replaceSubrange(startRange.lowerBound..<end, with: result)
                return stripProtocolJSON(from: modified, pattern: pattern)
            }
        }

        // Remove the protocol JSON entirely
        var modified = text
        modified.removeSubrange(startRange.lowerBound..<end)
        return stripProtocolJSON(from: modified, pattern: pattern)
    }

    private var segments: [TextContentSegment] {
        MarkdownTableParser.parseContent(displayText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(segments) { segment in
                switch segment {
                case .text(let text):
                    MarkdownTextView(text: text)
                case .table(let table):
                    MarkdownTableView(table: table)
                }
            }
        }
    }
}

// MARK: - Error Content View

struct ErrorContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    let error: ErrorContent

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(colors.destructive)

                Text(error.message)
                    .font(Typography.body)
                    .foregroundStyle(colors.destructive)
            }

            if let details = error.details {
                Text(details)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.destructive.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.destructive.opacity(0.3), lineWidth: BorderWidth.default)
        )
    }
}

// MARK: - Welcome Chat View

struct WelcomeChatView: View {
    @Environment(\.colorScheme) private var colorScheme

    let repoPath: String
    let tip: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(FakeData.welcomeMessage(for: repoPath))
                .font(Typography.body)
                .foregroundStyle(colors.mutedForeground)

            Text(tip)
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xl)
    }
}

// MARK: - No Workspace Selected View

struct NoWorkspaceSelectedView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 40))
                .foregroundStyle(colors.mutedForeground)

            VStack(spacing: Spacing.sm) {
                Text("No workspace selected")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)

                Text("Select a workspace from the sidebar or create a new one to start chatting")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Workspace Path Not Found View

struct WorkspacePathNotFoundView: View {
    @Environment(\.colorScheme) private var colorScheme

    let path: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(colors.destructive)

            VStack(spacing: Spacing.sm) {
                Text("Workspace not found")
                    .font(Typography.h4)
                    .foregroundStyle(colors.foreground)

                Text("The workspace directory no longer exists:")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)

                Text(path)
                    .font(Typography.code)
                    .foregroundStyle(colors.mutedForeground)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(colors.muted)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                Text("The folder may have been moved or deleted. Please check the path or remove this repository.")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Chat Header

struct ChatHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let projectName: String
    var onOpen: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Branch icon and name
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: IconSize.sm))

                Text("/\(projectName)")
                    .font(Typography.bodySmall)
            }
            .foregroundStyle(colors.mutedForeground)

            // Open button
            Button(action: onOpen) {
                HStack(spacing: Spacing.xs) {
                    Text("Open")
                    Image(systemName: "chevron.down")
                        .font(.system(size: IconSize.xs))
                }
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)

            Spacer()

            // Create PR button
            Button(action: {}) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.triangle.pull")
                    Text("Create PR")
                    Text("P")
                        .font(Typography.micro)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                        .background(colors.muted)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(colors.card)
    }
}
