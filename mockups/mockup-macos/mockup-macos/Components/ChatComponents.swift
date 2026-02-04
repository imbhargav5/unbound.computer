//
//  ChatComponents.swift
//  mockup-macos
//
//  Shadcn-styled chat components
//

import SwiftUI
import AppKit

// MARK: - Command Return Text Editor

/// Custom NSTextView that intercepts Cmd+Return and Shift+Tab
private class CommandReturnNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    var onShiftTab: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

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
        textView.onFocusChange = { isFocused in
            context.coordinator.isFocused.wrappedValue = isFocused
        }

        if let window = textView.window {
            if isFocused && window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            } else if !isFocused && window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
        }
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
                    Text("to toggle")
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
                isFocused: $isFocused,
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(isPlanMode ? colors.info : (isFocused ? colors.ring : colors.border), lineWidth: isPlanMode ? BorderWidth.thick : BorderWidth.default)
        )
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
                        Text(model.name)
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
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

struct ChatMessageView: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: ChatMessage
    var index: Int = 0  // For stagger animation

    @State private var isHovered = false
    @State private var hasAppeared = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Stagger delay based on index
    private var staggerDelay: Double {
        Double(index) * Duration.staggerInterval
    }

    private var isUser: Bool {
        message.role == .user
    }

    /// Group tool_use blocks under sub-agent containers when parent ids are present.
    private var displayContent: [MessageContent] {
        var grouped: [MessageContent] = []
        var subAgentIndexById: [String: Int] = [:]
        var pendingToolsByParent: [String: [ToolUse]] = [:]
        var pendingOrder: [ToolUse] = []

        for content in message.content {
            switch content {
            case .subAgentActivity(let activity):
                grouped.append(content)
                subAgentIndexById[activity.parentToolUseId] = grouped.count - 1

            case .toolUse(let toolUse):
                if toolUse.toolName == "Task", let toolUseId = toolUse.toolUseId {
                    let (subagentType, description) = taskDetails(from: toolUse.input)
                    var subAgent = SubAgentActivity(
                        parentToolUseId: toolUseId,
                        subagentType: subagentType,
                        description: description,
                        tools: [],
                        status: toolUse.status
                    )

                    if let pendingTools = pendingToolsByParent.removeValue(forKey: toolUseId) {
                        subAgent.tools.append(contentsOf: pendingTools)
                    }

                    grouped.append(.subAgentActivity(subAgent))
                    subAgentIndexById[toolUseId] = grouped.count - 1
                    continue
                }

                if let parentId = toolUse.parentToolUseId {
                    if let index = subAgentIndexById[parentId],
                       case .subAgentActivity(var subAgent) = grouped[index] {
                        subAgent.tools.append(toolUse)
                        grouped[index] = .subAgentActivity(subAgent)
                    } else {
                        pendingToolsByParent[parentId, default: []].append(toolUse)
                        pendingOrder.append(toolUse)
                    }
                } else {
                    grouped.append(content)
                }

            default:
                grouped.append(content)
            }
        }

        if !pendingOrder.isEmpty {
            for tool in pendingOrder {
                guard let parentId = tool.parentToolUseId,
                      pendingToolsByParent[parentId] != nil else {
                    continue
                }
                grouped.append(.toolUse(tool))
            }
        }

        return grouped
    }

    private var fileChanges: [FileChange] {
        displayContent.compactMap { content in
            if case .fileChange(let fileChange) = content {
                return fileChange
            }
            return nil
        }
    }

    private var nonFileContent: [MessageContent] {
        if isUser {
            return displayContent
        }
        return displayContent.filter { content in
            if case .fileChange = content {
                return false
            }
            return true
        }
    }

    private func taskDetails(from input: String?) -> (String, String) {
        guard let input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("unknown", "")
        }
        let subagentType = json["subagent_type"] as? String ?? "unknown"
        let description = json["description"] as? String ?? ""
        return (subagentType, description)
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

                // Render content blocks
                ForEach(nonFileContent) { content in
                    MessageContentView(content: content)
                }

                if !isUser && !fileChanges.isEmpty {
                    FileChangeSummaryView(fileChanges: fileChanges)
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
        .slideIn(isVisible: hasAppeared, from: .bottom, delay: staggerDelay)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Message Content View

struct MessageContentView: View {
    let content: MessageContent

    var body: some View {
        switch content {
        case .text(let textContent):
            TextContentView(textContent: textContent)

        case .codeBlock(let codeBlock):
            CodeBlockView(codeBlock: codeBlock)

        case .toolUse(let toolUse):
            ToolUseView(toolUse: toolUse)

        case .todoList(let todoList):
            TodoListView(todoList: todoList)

        case .fileChange(let fileChange):
            FileChangeView(fileChange: fileChange)

        case .error(let error):
            ErrorContentView(error: error)

        case .subAgentActivity(let activity):
            SubAgentActivityView(activity: activity)

        case .askUserQuestion:
            // Simplified for mockup
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

    var body: some View {
        Text(textContent.text)
            .font(Typography.body)
            .foregroundStyle(colors.foreground)
            .textSelection(.enabled)
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    let codeBlock: CodeBlock

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let filename = codeBlock.filename {
                    Text(filename)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                } else if !codeBlock.language.isEmpty {
                    Text(codeBlock.language)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }

                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(codeBlock.code, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(colors.muted)

            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code)
                    .font(Typography.code)
                    .foregroundStyle(colors.foreground)
                    .textSelection(.enabled)
                    .padding(Spacing.md)
            }
        }
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }
}

// MARK: - Tool Use View

struct ToolUseView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var actionText: String {
        ToolActivitySummary.actionLines(for: [toolUse]).first?.text ?? toolUse.toolName
    }

    private var hasDetails: Bool {
        (toolUse.input?.isEmpty == false) || (toolUse.output?.isEmpty == false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasDetails {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(actionText)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text(statusName)
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)

                    if hasDetails {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(colors.mutedForeground)
                    }
                }
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isExpanded && hasDetails {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ShadcnDivider()

                    if let input = toolUse.input, !input.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Input")
                                .font(Typography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(colors.mutedForeground)

                            ScrollView {
                                Text(input)
                                    .font(Typography.code)
                                    .foregroundStyle(colors.foreground)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 100)
                            .padding(Spacing.sm)
                            .background(colors.muted)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }
                        .padding(.horizontal, Spacing.md)
                    }

                    if let output = toolUse.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Output")
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
                        .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.bottom, Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusName: String {
        switch toolUse.status {
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        switch toolUse.status {
        case .running: return colors.info
        case .completed: return colors.success
        case .failed: return colors.destructive
        }
    }
}

// MARK: - Todo List View

struct TodoListView: View {
    @Environment(\.colorScheme) private var colorScheme

    let todoList: TodoList

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(todoList.items) { item in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: statusIcon(for: item.status))
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(statusColor(for: item.status))

                    Text(item.content)
                        .font(Typography.bodySmall)
                        .foregroundStyle(item.status == .completed ? colors.mutedForeground : colors.foreground)
                        .strikethrough(item.status == .completed)
                }
            }
        }
        .padding(Spacing.md)
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }

    private func statusIcon(for status: TodoStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private func statusColor(for status: TodoStatus) -> Color {
        switch status {
        case .pending: return colors.mutedForeground
        case .inProgress: return colors.info
        case .completed: return colors.success
        }
    }
}

// MARK: - File Change View

struct FileChangeView: View {
    @Environment(\.colorScheme) private var colorScheme

    let fileChange: FileChange

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: changeTypeIcon)
                .font(.system(size: IconSize.sm))
                .foregroundStyle(changeTypeColor)

            Text(fileChange.filePath)
                .font(Typography.bodySmall)
                .foregroundStyle(colors.foreground)

            Spacer()

            if fileChange.linesAdded > 0 || fileChange.linesRemoved > 0 {
                HStack(spacing: Spacing.xs) {
                    Text("+\(fileChange.linesAdded)")
                        .font(Typography.caption)
                        .foregroundStyle(colors.success)
                    Text("-\(fileChange.linesRemoved)")
                        .font(Typography.caption)
                        .foregroundStyle(colors.destructive)
                }
            }
        }
        .padding(Spacing.sm)
        .background(colors.muted)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var changeTypeIcon: String {
        switch fileChange.changeType {
        case .created: return "plus"
        case .modified: return "pencil"
        case .deleted: return "minus"
        case .renamed: return "arrow.right"
        }
    }

    private var changeTypeColor: Color {
        switch fileChange.changeType {
        case .created: return colors.success
        case .modified: return colors.warning
        case .deleted: return colors.destructive
        case .renamed: return colors.info
        }
    }
}

// MARK: - File Change Summary View

struct FileChangeSummaryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let fileChanges: [FileChange]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var totalAdditions: Int {
        fileChanges.reduce(0) { $0 + $1.linesAdded }
    }

    private var totalDeletions: Int {
        fileChanges.reduce(0) { $0 + $1.linesRemoved }
    }

    private var headerTitle: String {
        let count = fileChanges.count
        return "\(count) file\(count == 1 ? "" : "s") changed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(Spacing.md)

            if !fileChanges.isEmpty {
                ShadcnDivider()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(fileChanges) { fileChange in
                        FileChangeSummaryRow(fileChange: fileChange)

                        if fileChange.id != fileChanges.last?.id {
                            ShadcnDivider()
                        }
                    }
                }
            }
        }
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(headerTitle)
                .font(Typography.bodySmall)
                .foregroundStyle(colors.foreground)

            if totalAdditions > 0 || totalDeletions > 0 {
                HStack(spacing: Spacing.xs) {
                    if totalAdditions > 0 {
                        Text("+\(totalAdditions)")
                            .font(Typography.caption)
                            .foregroundStyle(colors.success)
                    }
                    if totalDeletions > 0 {
                        Text("-\(totalDeletions)")
                            .font(Typography.caption)
                            .foregroundStyle(colors.destructive)
                    }
                }
            }

            Spacer()

            Button(action: {}) {
                HStack(spacing: Spacing.xs) {
                    Text("Undo")
                    Image(systemName: "arrow.uturn.backward")
                }
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FileChangeSummaryRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let fileChange: FileChange

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(fileChange.filePath)
                .font(Typography.code)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if fileChange.linesAdded > 0 || fileChange.linesRemoved > 0 {
                HStack(spacing: Spacing.xs) {
                    if fileChange.linesAdded > 0 {
                        Text("+\(fileChange.linesAdded)")
                            .font(Typography.caption)
                            .foregroundStyle(colors.success)
                    }
                    if fileChange.linesRemoved > 0 {
                        Text("-\(fileChange.linesRemoved)")
                            .font(Typography.caption)
                            .foregroundStyle(colors.destructive)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
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

// MARK: - Tool Activity Summary

private struct ToolActionLine: Identifiable {
    let id = UUID()
    let text: String
}

private enum ToolActivitySummary {
    static func summary(for activity: SubAgentActivity) -> String {
        let counts = categoryCounts(toolNames: activity.tools.map { $0.toolName })
        let countsText = formatCounts(counts)
        guard let verb = verbForSubagent(type: activity.subagentType, status: activity.status) else {
            return "\(activity.subagentType) activity"
        }
        if countsText.isEmpty {
            return verb
        }
        return "\(verb) \(countsText)"
    }

    static func actionLines(for tools: [ToolUse]) -> [ToolActionLine] {
        tools.map { tool in
            let text: String
            let filePath = inputValue(tool.input, key: "file_path") ?? tool.input
            let pattern = inputValue(tool.input, key: "pattern") ?? tool.input ?? ""
            let command = inputValue(tool.input, key: "command") ?? tool.input ?? ""
            let query = inputValue(tool.input, key: "query") ?? tool.input ?? ""
            let url = inputValue(tool.input, key: "url") ?? tool.input
            switch tool.toolName {
            case "Read":
                text = "Read \(fileLabel(filePath))"
            case "Write":
                text = "Wrote \(fileLabel(filePath))"
            case "Edit":
                text = "Edited \(fileLabel(filePath))"
            case "Grep":
                text = "Searched for \(pattern)"
            case "Glob":
                text = "Searched files by \(pattern)"
            case "Bash":
                text = "Ran \(command)"
            case "WebSearch":
                text = "Searched the web for \(query)"
            case "WebFetch":
                text = "Fetched \(hostLabel(url))"
            default:
                text = fallbackText(toolName: tool.toolName, preview: tool.input ?? "")
            }
            return ToolActionLine(text: text.trimmingCharacters(in: .whitespaces))
        }
        .filter { !$0.text.isEmpty }
    }

    private static func verbForSubagent(type: String, status: ToolStatus) -> String? {
        let lower = type.lowercased()
        let isRunning = status == .running
        switch lower {
        case "explore":
            return isRunning ? "Exploring" : "Explored"
        case "plan":
            return isRunning ? "Planning" : "Planned"
        case "bash":
            return isRunning ? "Running" : "Ran"
        case "general-purpose":
            return isRunning ? "Working" : "Worked"
        default:
            return nil
        }
    }

    private static func categoryCounts(toolNames: [String]) -> (files: Int, searches: Int, commands: Int, web: Int) {
        var files = 0
        var searches = 0
        var commands = 0
        var web = 0

        for name in toolNames {
            switch name {
            case "Read", "Write", "Edit":
                files += 1
            case "Grep", "Glob":
                searches += 1
            case "Bash":
                commands += 1
            case "WebSearch", "WebFetch":
                web += 1
            default:
                break
            }
        }
        return (files, searches, commands, web)
    }

    private static func formatCounts(_ counts: (files: Int, searches: Int, commands: Int, web: Int)) -> String {
        var parts: [String] = []
        if counts.files > 0 {
            parts.append(formatCount(counts.files, singular: "file", plural: "files"))
        }
        if counts.searches > 0 {
            parts.append(formatCount(counts.searches, singular: "search", plural: "searches"))
        }
        if counts.commands > 0 {
            parts.append(formatCount(counts.commands, singular: "command", plural: "commands"))
        }
        if counts.web > 0 {
            parts.append(formatCount(counts.web, singular: "web request", plural: "web requests"))
        }
        return parts.joined(separator: ", ")
    }

    private static func formatCount(_ count: Int, singular: String, plural: String) -> String {
        if count == 1 {
            return "1 \(singular)"
        }
        return "\(count) \(plural)"
    }

    private static func inputValue(_ input: String?, key: String) -> String? {
        guard let input, let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json[key] as? String
    }

    private static func fileLabel(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func hostLabel(_ urlString: String?) -> String {
        guard let urlString, !urlString.isEmpty else { return "" }
        if let url = URL(string: urlString), let host = url.host {
            return host
        }
        return urlString
    }

    private static func fallbackText(toolName: String, preview: String) -> String {
        if preview.isEmpty {
            return toolName
        }
        return "\(toolName) \(preview)"
    }
}

// MARK: - Sub-Agent Activity View

struct SubAgentActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    let activity: SubAgentActivity

    @State private var isExpanded = true
    @State private var hasAppeared = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var summaryText: String {
        ToolActivitySummary.summary(for: activity)
    }

    private var actionLines: [ToolActionLine] {
        ToolActivitySummary.actionLines(for: activity.tools)
    }

    private var hasDetails: Bool {
        !actionLines.isEmpty || (activity.result?.isEmpty == false)
    }

    private var detailPaddingLeading: CGFloat {
        Spacing.md + IconSize.sm + Spacing.sm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded && hasDetails {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ShadcnDivider()
                        .padding(.horizontal, Spacing.md)

                    ForEach(actionLines) { line in
                        Text(line.text)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                            .padding(.leading, detailPaddingLeading)
                            .padding(.trailing, Spacing.md)
                    }

                    if let result = activity.result, !result.isEmpty {
                        Text(result)
                            .font(Typography.caption)
                            .foregroundStyle(colors.foreground)
                            .padding(.leading, detailPaddingLeading)
                            .padding(.trailing, Spacing.md)
                            .padding(.top, Spacing.xs)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .scaleFade(isVisible: hasAppeared)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                hasAppeared = true
            }
        }
    }

    private var header: some View {
        Button {
            if hasDetails {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                statusIcon

                Text(summaryText)
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)

                Spacer()

                if hasDetails {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch activity.status {
        case .running:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: IconSize.sm, height: IconSize.sm)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: IconSize.xs))
                .foregroundStyle(colors.mutedForeground)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: IconSize.xs))
                .foregroundStyle(colors.destructive)
        }
    }
}

// MARK: - Multiple Sub-Agents View

/// Displays multiple sub-agents in a stacked view
struct SubAgentStackView: View {
    @Environment(\.colorScheme) private var colorScheme

    let activities: [SubAgentActivity]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(activities) { activity in
                SubAgentActivityView(activity: activity)
            }
        }
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
                    .font(Typography.bodySmall)
                    .lineLimit(1)
            }
            .foregroundStyle(colors.mutedForeground)

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: 40)
        .background(colors.card)
    }
}

// MARK: - Previews

#Preview("Sub-Agent Activity - Running") {
    VStack(spacing: Spacing.lg) {
        SubAgentActivityView(activity: FakeData.exploreAgentRunning)
        SubAgentActivityView(activity: FakeData.generalAgentActivity)
    }
    .padding(Spacing.lg)
    .background(ShadcnColors.Dark.background)
    .preferredColorScheme(.dark)
}

#Preview("Sub-Agent Activity - Completed") {
    VStack(spacing: Spacing.lg) {
        SubAgentActivityView(activity: FakeData.exploreAgentCompleted)
        SubAgentActivityView(activity: FakeData.planAgentActivity)
    }
    .padding(Spacing.lg)
    .background(ShadcnColors.Dark.background)
    .preferredColorScheme(.dark)
}

#Preview("Sub-Agent Stack - Parallel Execution") {
    SubAgentStackView(activities: [
        FakeData.exploreAgentRunning,
        FakeData.bashAgentActivity,
        FakeData.exploreAgentCompleted
    ])
    .padding(Spacing.lg)
    .background(ShadcnColors.Dark.background)
    .preferredColorScheme(.dark)
}

#Preview("Chat with Sub-Agents") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            ForEach(Array(FakeData.messagesWithSubAgents.enumerated()), id: \.element.id) { index, message in
                ChatMessageView(message: message, index: index)
            }
        }
        .padding(.vertical, Spacing.lg)
    }
    .background(ShadcnColors.Dark.background)
    .preferredColorScheme(.dark)
}
