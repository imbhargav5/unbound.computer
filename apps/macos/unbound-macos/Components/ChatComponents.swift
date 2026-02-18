//
//  ChatComponents.swift
//  unbound-macos
//
//  Shadcn-styled chat components
//

import SwiftUI
import AppKit
import Logging
import ClaudeConversationTimeline

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
        FontRegistration.registerFonts()
        textView.font = NSFont(name: "Geist-Regular", size: 14) ?? NSFont.systemFont(ofSize: 14)
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
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0

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
    @State private var isPlanDropdownOpen: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var isCompact: Bool {
        !isFocused && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var borderColor: Color {
        if isCompact {
            return Color(hex: "2A2A2A")
        }
        return isPlanMode ? Color(hex: "3B82F6") : Color(hex: "F59E0B")
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
                        .foregroundStyle(Color(hex: "0D0D0D"))
                        .frame(width: 32, height: 32)
                        .background(isPlanMode && !isCompact ? Color(hex: "3B82F6") : Color(hex: "F59E0B"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var planHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "map")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "3B82F6"))
            Text("Plan mode — Claude will create a plan before making changes")
                .font(GeistFont.sans(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: "7BA4E8"))
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .padding(.trailing, 10)
        .padding(.bottom, 6)
        .background(Color(hex: "3B82F6").opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .frame(height: 28)
    }

    private var plusMenuButton: some View {
        Button {
            withAnimation(.easeInOut(duration: Duration.default)) {
                isPlanDropdownOpen.toggle()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "8A8A8A"))
                .frame(width: 24, height: 24)
                .background(Color(hex: "1A1A1A"))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .stroke(Color(hex: "2A2A2A"), lineWidth: BorderWidth.default)
                )
        }
        .buttonStyle(.plain)
    }

    private var planModeDropdown: some View {
        VStack(spacing: 2) {
            Button {
                isPlanDropdownOpen = false
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "999999"))
                    Text("Add Attachments")
                        .font(GeistFont.sans(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: "CCCCCC"))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color(hex: "2A2A2A"))
                .frame(height: 1)

            Button {
                isPlanMode.toggle()
                isPlanDropdownOpen = false
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "map")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "3B82F6"))
                        Text("Plan mode")
                            .font(GeistFont.sans(size: 13, weight: .regular))
                            .foregroundStyle(Color(hex: "CCCCCC"))
                    }

                    Spacer(minLength: 0)

                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isPlanMode ? Color(hex: "3B82F6") : Color(hex: "333333"))
                            .frame(width: 32, height: 18)

                        HStack(spacing: 0) {
                            if isPlanMode {
                                Spacer(minLength: 0)
                            }
                            Circle()
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                            if !isPlanMode {
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(2)
                    }
                    .animation(.easeInOut(duration: Duration.fast), value: isPlanMode)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: 220)
        .background(Color(hex: "141414"))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "2A2A2A"), lineWidth: BorderWidth.default)
        )
        .shadow(color: Color.black.opacity(0.38), radius: 24, y: 8)
    }

    var body: some View {
        VStack(spacing: isCompact ? 0 : Spacing.md) {
            if !isCompact && isPlanMode {
                planHeader
            }

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
                .frame(height: 18)
            }

            HStack {
                if isCompact {
                    Text("What do you want to build?")
                        .font(GeistFont.sans(size: 14, weight: .regular))
                        .foregroundStyle(Color(hex: "525252"))
                } else {
                    ModelSelector(
                        selectedModel: $selectedModel,
                        selectedThinkMode: $selectedThinkMode,
                        isPlanMode: isPlanMode
                    )
                    .fixedSize()
                }

                Spacer(minLength: 0)

                if !isCompact {
                    HStack(spacing: 12) {
                        plusMenuButton
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: "8A8A8A"))
                    }
                    .padding(.trailing, 12)
                }

                sendButton
            }
            .frame(height: 32)
        }
        .padding(Spacing.lg)
        .background(Color(hex: "111111"))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl)
                .stroke(borderColor, lineWidth: BorderWidth.default)
        )
        .overlay(alignment: .bottomTrailing) {
            if !isCompact && isPlanDropdownOpen {
                planModeDropdown
                    .offset(y: 8)
                    .zIndex(1)
            }
        }
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
        .animation(.easeInOut(duration: Duration.fast), value: isPlanDropdownOpen)
        .onChange(of: isCompact) { _, compact in
            if compact {
                isPlanDropdownOpen = false
            }
        }
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Model Selector

struct ModelSelector: View {
    @Binding var selectedModel: AIModel
    @Binding var selectedThinkMode: ThinkMode
    let isPlanMode: Bool

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AIModel.allModels) { model in
                    Button {
                        selectedModel = model
                        if !model.supportsThinking && selectedThinkMode != .none {
                            selectedThinkMode = .none
                        }
                    } label: {
                        Label(model.name, systemImage: model.iconName)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selectedModel.iconName)
                        .font(.system(size: 14))
                    Text(selectedModel.name)
                        .font(GeistFont.sans(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(hex: "8A8A8A"))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Rectangle()
                .fill(Color(hex: "333333"))
                .frame(width: 1, height: 16)

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
                                        .font(Typography.caption)
                                        .foregroundStyle(Color(hex: "A3A3A3"))
                                }
                            } icon: {
                                Image(systemName: mode.iconName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedThinkMode.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "F59E0B"))
                        Text(selectedThinkMode.name)
                            .font(GeistFont.sans(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "A3A3A3"))
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            if isPlanMode {
                Rectangle()
                    .fill(Color(hex: "333333"))
                    .frame(width: 1, height: 16)

                HStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "3B82F6"))
                    Text("Plan")
                        .font(GeistFont.sans(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "93B4F6"))
                }
            }
        }
    }
}

// MARK: - Chat Message View

enum ChatMessageRenderBlock: Identifiable {
    case content(MessageContent)
    case standaloneTools([ToolUse])
    case parallelAgents([SubAgentActivity])

    var id: String {
        switch self {
        case .content(let content):
            return "content:\(content.id.uuidString)"
        case .standaloneTools(let tools):
            let identity = tools.map { $0.toolUseId ?? $0.id.uuidString }.joined(separator: "|")
            return "tools:\(identity)"
        case .parallelAgents(let activities):
            let identity = activities.map(\.parentToolUseId).joined(separator: "|")
            return "parallel:\(identity)"
        }
    }
}

enum ChatMessageRenderPlanner {
    static func renderBlocks(from displayContent: [MessageContent], isUser: Bool) -> [ChatMessageRenderBlock] {
        var blocks: [ChatMessageRenderBlock] = []
        var pendingStandaloneTools: [ToolUse] = []
        var pendingSubAgents: [SubAgentActivity] = []

        func flushPendingTools() {
            guard !pendingStandaloneTools.isEmpty else { return }
            blocks.append(.standaloneTools(pendingStandaloneTools))
            pendingStandaloneTools.removeAll(keepingCapacity: true)
        }

        func flushPendingSubAgents() {
            guard !pendingSubAgents.isEmpty else { return }
            blocks.append(.parallelAgents(pendingSubAgents))
            pendingSubAgents.removeAll(keepingCapacity: true)
        }

        for content in displayContent {
            if !isUser, case .fileChange = content {
                continue
            }

            if case .toolUse(let toolUse) = content {
                flushPendingSubAgents()
                pendingStandaloneTools.append(toolUse)
                continue
            }

            if case .subAgentActivity(let activity) = content {
                flushPendingTools()
                pendingSubAgents.append(activity)
                continue
            }

            flushPendingTools()
            flushPendingSubAgents()
            blocks.append(.content(content))
        }

        flushPendingTools()
        flushPendingSubAgents()
        return blocks
    }
}

struct ChatMessageView: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: ChatMessage
    var animationIndex: Int = 0  // For stagger animation
    var onQuestionSubmit: ((AskUserQuestion) -> Void)?
    var shouldAnimate: Bool = false
    var onRowAppear: (() -> Void)?

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
        ChatMessageRenderPlanner.renderBlocks(from: displayContent, isUser: isUser)
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
            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.md) {
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
                    case .parallelAgents(let activities):
                        ParallelAgentsView(activities: activities)
                    }
                }

                if !isUser && !fileChanges.isEmpty {
                    FileChangeSummaryView(fileChanges: fileChanges)
                }
            }
            .padding(.vertical, isUser ? 10 : 0)
            .padding(.horizontal, isUser ? 14 : 0)
            .background(
                Group {
                    if isUser {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colors.chatUserBubbleBackground)
                    }
                }
            )
            .overlay(
                Group {
                    if isUser {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(colors.chatUserBubbleBorder, lineWidth: BorderWidth.default)
                    }
                }
            )

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
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
            ParallelAgentsView(activities: [activity])

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
                        .foregroundStyle(colors.textMuted)
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
