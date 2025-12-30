//
//  ChatComponents.swift
//  unbound-macos
//
//  Shadcn-styled chat components
//

import SwiftUI
import AppKit

// MARK: - Chat Input Field

struct ChatInputField: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    @Binding var selectedModel: AIModel
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Text input area
            TextEditor(text: $text)
                .font(Typography.body)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .onKeyPress(.return, phases: .down) { keyPress in
                    // Command+Enter to send
                    if keyPress.modifiers.contains(.command) && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                        return .handled
                    }
                    return .ignored
                }

            // Bottom toolbar
            HStack(spacing: Spacing.md) {
                // Model selector
                ModelSelector(selectedModel: $selectedModel)

                // Action buttons
                HStack(spacing: Spacing.sm) {
                    IconButton(systemName: "doc.on.clipboard", action: {})
                    IconButton(systemName: "doc.fill", action: {})
                }

                Spacer()

                // Additional actions
                HStack(spacing: Spacing.sm) {
                    IconButton(systemName: "tag", action: {})
                    IconButton(systemName: "paperclip", action: {})

                    // Send button
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: IconSize.xxl))
                            .foregroundStyle(text.isEmpty ? colors.mutedForeground : colors.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(isFocused ? colors.ring : colors.border, lineWidth: BorderWidth.default)
        )
        .animation(.easeInOut(duration: Duration.fast), value: isFocused)
    }
}

// MARK: - Model Selector

struct ModelSelector: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedModel: AIModel

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Menu {
            ForEach(AIModel.allModels) { model in
                Button {
                    selectedModel = model
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
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: ChatMessage
    var onQuestionSubmit: ((AskUserQuestion) -> Void)?

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Get all copyable text from the message
    private var copyableText: String {
        message.content.compactMap { content in
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
            case .askUserQuestion(let question):
                return question.question
            }
        }.joined(separator: "\n\n")
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copyableText, forType: .string)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Avatar
            Circle()
                .fill(message.role == .user ? colors.info : colors.primary)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .overlay(
                    Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(message.role == .user ? colors.foreground : colors.primaryForeground)
                )

            // Content
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text(message.role == .user ? "You" : "Assistant")
                        .font(Typography.label)
                        .foregroundStyle(colors.foreground)

                    if message.isStreaming {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    Spacer()

                    // Copy button (shown on hover)
                    if isHovered && !message.isStreaming {
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: IconSize.sm))
                                .foregroundStyle(colors.mutedForeground)
                        }
                        .buttonStyle(.plain)
                        .help("Copy message")
                    }
                }

                // Render content blocks
                ForEach(message.content) { content in
                    MessageContentView(
                        content: content,
                        onQuestionSubmit: onQuestionSubmit
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
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
}

// MARK: - Message Content View

struct MessageContentView: View {
    let content: MessageContent
    var onQuestionSubmit: ((AskUserQuestion) -> Void)?

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
            ToolUseView(toolUse: toolUse)

        case .error(let error):
            ErrorContentView(error: error)
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
