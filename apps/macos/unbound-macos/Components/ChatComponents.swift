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
    var onFocusChange: ((Bool) -> Void)?
    var pendingFocus: Bool = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, pendingFocus {
            window.makeFirstResponder(self)
            pendingFocus = false
        }
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocusChange?(true)
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            onFocusChange?(false)
        }
        return didResign
    }

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
    @Binding var isFocused: Bool
    let colorScheme: ColorScheme
    var onCommandReturn: () -> Void
    var onShiftTab: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CommandReturnNSTextView()
        textView.onCommandReturn = onCommandReturn
        textView.onShiftTab = onShiftTab
        textView.onFocusChange = { isFocused in
            context.coordinator.isFocused.wrappedValue = isFocused
        }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor(hex: colorScheme == .dark ? "E5E5E5" : "0D0D0D")
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
        textView.onFocusChange = { isFocused in
            context.coordinator.isFocused.wrappedValue = isFocused
        }

        if let window = textView.window {
            if isFocused && window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            } else if !isFocused && window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
            textView.pendingFocus = false
        } else if isFocused {
            textView.pendingFocus = true
        }

        textView.textColor = NSColor(hex: colorScheme == .dark ? "E5E5E5" : "0D0D0D")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
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

    @State private var isFocused: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var isCompact: Bool {
        !isFocused && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButton: some View {
        Group {
            if isStreaming {
                Button(action: { onCancel?() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(colors.primaryForeground)
                        .frame(width: 32, height: 32)
                        .background(colors.destructive)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.primaryForeground)
                        .frame(width: 32, height: 32)
                        .background(colors.primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    var body: some View {
        VStack(spacing: isCompact ? 0 : Spacing.md) {
            // Plan mode indicator (expanded + plan mode only)
            if isPlanMode && !isCompact {
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
            }

            // Text editor (expanded only)
            if !isCompact {
                CommandReturnTextEditor(
                    text: $text,
                    isFocused: $isFocused,
                    colorScheme: colorScheme,
                    onCommandReturn: {
                        if !isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend()
                        }
                    },
                    onShiftTab: {
                        isPlanMode.toggle()
                    }
                )
                .frame(minHeight: 40, maxHeight: 120)
            }

            // Footer row
            HStack {
                if isCompact {
                    Text("What do you want to build?")
                        .font(Typography.body)
                        .foregroundStyle(Color(hex: "525252"))
                } else {
                    HStack(spacing: Spacing.sm) {
                        ModelSelector(selectedModel: $selectedModel, selectedThinkMode: $selectedThinkMode)
                    }
                    .fixedSize()
                }

                Spacer()

                if !isCompact {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18))
                            .foregroundStyle(colors.gray8A8)
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 18))
                            .foregroundStyle(colors.gray8A8)
                    }
                }

                sendButton
            }
        }
        .padding(Spacing.lg)
        .background(isPlanMode && !isCompact ? colors.info.opacity(0.08) : colors.input)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl)
                .stroke(
                    isCompact ? colors.borderInput :
                        (isPlanMode ? colors.info : (isFocused ? colors.ring : colors.borderInput)),
                    lineWidth: isPlanMode && !isCompact ? BorderWidth.thick : BorderWidth.default
                )
        )
        .overlay {
            if isCompact {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isFocused = true
                    }
            }
        }
        .animation(.snappy(duration: 0.3), value: isCompact)
        .animation(.easeInOut(duration: Duration.fast), value: isFocused)
        .animation(.easeInOut(duration: Duration.fast), value: isPlanMode)
        .onAppear {
            isFocused = true
        }
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
                }
                .foregroundStyle(colors.mutedForeground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .background(colors.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

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
                                        .foregroundStyle(colors.mutedForeground)
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
                    }
                    .foregroundStyle(selectedThinkMode == .none ? colors.mutedForeground : colors.info)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .background(selectedThinkMode == .none ? colors.muted : colors.info.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }
}

// MARK: - Chat Message View

private enum ChatMessageRenderBlock: Identifiable {
    case content(MessageContent)
    case standaloneTools([ToolUse])

    var id: String {
        switch self {
        case .content(let content):
            return "content:\(content.id.uuidString)"
        case .standaloneTools(let tools):
            let identity = tools.map { $0.toolUseId ?? $0.id.uuidString }.joined(separator: "|")
            return "tools:\(identity)"
        }
    }
}

struct ChatMessageView: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: ChatMessage
    var animationIndex: Int = 0  // For stagger animation
    var onQuestionSubmit: ((AskUserQuestion) -> Void)?
    var shouldAnimate: Bool = false
    var onRowAppear: (() -> Void)?

    @State private var isHovered = false
    @State private var hasAppeared = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Stagger delay based on index
    private var staggerDelay: Double {
        Double(animationIndex) * Duration.staggerInterval
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

    private var fileChanges: [FileChange] {
        displayContent.compactMap { content in
            if case .fileChange(let fileChange) = content {
                return fileChange
            }
            return nil
        }
    }

    private var renderBlocks: [ChatMessageRenderBlock] {
        var blocks: [ChatMessageRenderBlock] = []
        var pendingStandaloneTools: [ToolUse] = []

        func flushPendingTools() {
            guard !pendingStandaloneTools.isEmpty else { return }
            blocks.append(.standaloneTools(pendingStandaloneTools))
            pendingStandaloneTools.removeAll()
        }

        for content in displayContent {
            if !isUser, case .fileChange = content {
                continue
            }

            if case .toolUse(let toolUse) = content {
                pendingStandaloneTools.append(toolUse)
                continue
            }

            flushPendingTools()
            blocks.append(.content(content))
        }

        flushPendingTools()
        return blocks
    }

    /// Get all copyable text from the message
    private var copyableText: String {
        displayContent.compactMap { content in
            switch content {
            case .text(let textContent):
                return textContent.text
            case .codeBlock(let codeBlock):
                return "```\(codeBlock.language)\n\(codeBlock.code)\n```"
            case .error(let error):
                return "Error: \(error.message)\(error.details.map { "\n\($0)" } ?? "")"
            case .todoList(let todoList):
                return todoList.items.map { "- [\($0.status == .completed ? "x" : " ")] \($0.content)" }.joined(separator: "\n")
            case .fileChange(let fileChange):
                return "\(fileChange.changeType.rawValue): \(fileChange.filePath)"
            case .toolUse(let toolUse):
                // Only include bash commands as they're useful to copy
                if toolUse.toolName == "Bash", let input = toolUse.input {
                    if let data = input.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let command = json["command"] as? String {
                        return command
                    }
                }
                return nil
            case .subAgentActivity:
                // Sub-agent activities don't have useful copyable content
                return nil
            case .askUserQuestion(let question):
                return question.question
            case .eventPayload:
                return nil
            }
        }.joined(separator: "\n\n")
    }

    /// Whether this message has meaningful content worth copying
    private var hasCopyableContent: Bool {
        // User messages are always copyable
        if isUser { return true }

        // Check if there's actual text content, code blocks, or useful tool output
        for content in displayContent {
            switch content {
            case .text(let textContent):
                if !textContent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            case .codeBlock:
                return true
            case .error:
                return true
            case .todoList:
                return true
            case .toolUse(let toolUse):
                // Only Bash commands are worth copying
                if toolUse.toolName == "Bash" && toolUse.input != nil {
                    return true
                }
            case .askUserQuestion:
                return true
            case .fileChange, .subAgentActivity, .eventPayload:
                continue
            }
        }
        return false
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copyableText, forType: .string)
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var messageRow: some View {
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

                // Render content blocks (deduplicated and grouped for display)
                ForEach(renderBlocks) { block in
                    switch block {
                    case .content(let content):
                        MessageContentView(
                            content: content,
                            onQuestionSubmit: onQuestionSubmit
                        )
                    case .standaloneTools(let tools):
                        StandaloneToolCallsView(historyTools: tools)
                    }
                }

                if !isUser && !fileChanges.isEmpty {
                    FileChangeSummaryView(fileChanges: fileChanges)
                }
            }
            .padding(.vertical, isUser ? 10 : 0)
            .padding(.horizontal, isUser ? Spacing.lg : 0)
            .background(
                Group {
                    if isUser {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "2A2A2A"))
                    }
                }
            )

            // Copy button on the right (only show when hovered and has copyable content)
            if isHovered && !message.isStreaming && hasCopyableContent {
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
                .buttonStyle(.plain)
                .help("Copy message")
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, isUser ? Spacing.lg : Spacing.sm)
        .padding(.bottom, Spacing.sm)
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
    }

    var body: some View {
        Group {
            if shouldAnimate {
                messageRow
                    .slideIn(isVisible: hasAppeared, from: .bottom, delay: staggerDelay)
                    .onAppear {
                        onRowAppear?()
                        // Small delay to ensure the view is ready
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            hasAppeared = true
                        }
                    }
            } else {
                messageRow
                    .onAppear {
                        onRowAppear?()
                    }
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
            SubAgentView(activity: activity)

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

    /// Protocol payload types that should never be surfaced as text rows.
    private static let protocolTypes: Set<String> = ["user", "system", "assistant", "result", "tool_result"]

    private var displayText: String {
        let trimmed = textContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return isProtocolArtifact(trimmed) ? "" : trimmed
    }

    private func isProtocolArtifact(_ text: String) -> Bool {
        guard text.hasPrefix("{"), text.hasSuffix("}"),
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = (json["type"] as? String)?.lowercased() else {
            return false
        }

        return Self.protocolTypes.contains(type)
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
    let path: String

    var body: some View {
        ErrorStateView(
            icon: "folder.badge.questionmark",
            title: "Workspace not found",
            message: "The workspace directory no longer exists. The folder may have been moved or deleted.",
            detail: path
        )
    }
}

// MARK: - Chat Header

struct ChatHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let sessionTitle: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Session title
            HStack(spacing: Spacing.sm) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: IconSize.sm))

                Text(sessionTitle)
                    .font(Typography.toolbar)
                    .lineLimit(1)
            }
            .foregroundStyle(colors.mutedForeground)

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: LayoutMetrics.toolbarHeight)
        .background(colors.toolbarBackground)
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
