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
                ForEach(message.content) { content in
                    MessageContentView(content: content)
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

        case .askUserQuestion, .subAgentActivity:
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

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Status indicator
            Group {
                switch toolUse.status {
                case .running:
                    ProgressView()
                        .scaleEffect(0.6)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colors.success)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(colors.destructive)
                }
            }
            .frame(width: IconSize.md)

            // Tool name
            Text(toolUse.toolName)
                .font(Typography.bodySmall)
                .fontWeight(.medium)
                .foregroundStyle(colors.foreground)

            // Input preview
            if let input = toolUse.input {
                Text(input)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(Spacing.sm)
        .background(colors.muted)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
