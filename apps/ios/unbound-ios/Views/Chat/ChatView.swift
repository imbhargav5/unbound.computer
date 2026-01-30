import Logging
import SwiftUI

private let logger = Logger(label: "app.ui.chat")

struct ChatView: View {
    let chat: Chat?
    var project: Project? = nil

    @State private var viewModel = ChatViewModel()

    private var chatTitle: String {
        chat?.title ?? "New Chat"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.spacingM) {
                        if viewModel.messages.isEmpty {
                            welcomeView
                                .padding(.top, 60)
                        } else {
                            ForEach(viewModel.messages) { message in
                                messageView(for: message)
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.95).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }

                            // Live tool usage indicator with history
                            if !viewModel.completedTools.isEmpty || viewModel.currentToolState != nil {
                                ToolHistoryStackView(
                                    completedTools: viewModel.completedTools,
                                    currentTool: viewModel.currentToolState
                                )
                                .id("toolUsage")
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }

                            if viewModel.isTyping {
                                typingIndicator
                                    .id("typing")
                            }
                        }

                        // Bottom anchor for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.vertical, AppTheme.spacingM)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isTyping) { _, newValue in
                    if newValue {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            // Bottom input area (changes based on MCQ state)
            bottomInputView
        }
        .background(AppTheme.backgroundPrimary)
        .navigationTitle(chatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: AppTheme.spacingS) {
                    if viewModel.sessionManager.hasActiveSessions {
                        DynamicIslandButton(
                            activeCount: viewModel.sessionManager.sessions.count,
                            hasGenerating: viewModel.hasGeneratingSessions
                        ) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                viewModel.showDynamicIsland = true
                            }
                        }
                    }

                    GitActionsMenu(
                        onCreatePR: { viewModel.handleGitAction("Creating PR...") },
                        onPushChanges: { viewModel.handleGitAction("Pushing changes...") },
                        onViewFullDiff: { viewModel.handleGitAction("Loading diff...") },
                        onCopyChanges: { viewModel.handleGitAction("Copied to clipboard") },
                        onCommit: { viewModel.handleGitAction("Committing changes...") }
                    )
                }
            }
        }
        .dynamicIslandOverlay(
            isExpanded: $viewModel.showDynamicIsland,
            sessions: viewModel.sessionManager.sessions
        ) { session in
            // Handle session tap - could navigate to that chat
            logger.debug("Navigate to: \(session.projectName) - \(session.chatTitle)")
            viewModel.showDynamicIsland = false
        }
        .onAppear {
            viewModel.loadMessages(for: chat)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    private var welcomeView: some View {
        VStack(spacing: AppTheme.spacingL) {
            ClaudeAvatarView(size: 64)

            VStack(spacing: AppTheme.spacingS) {
                Text("Chat with Claude")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Ask questions, get help with code, debug issues, or explore new ideas for your project.")
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Suggested prompts
            VStack(spacing: AppTheme.spacingS) {
                SuggestedPromptButton(text: "Explain this codebase structure") {
                    viewModel.inputText = "Explain this codebase structure"
                }
                SuggestedPromptButton(text: "Help me debug an issue") {
                    viewModel.inputText = "Help me debug an issue"
                }
                SuggestedPromptButton(text: "Suggest improvements") {
                    viewModel.inputText = "Suggest improvements for this project"
                }
            }
        }
        .padding(.horizontal, AppTheme.spacingXL)
    }

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: AppTheme.spacingS) {
            ClaudeAvatarView(size: 28)
                .padding(.bottom, 4)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    TypingDot(delay: Double(index) * 0.15, index: index)
                }
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, AppTheme.spacingM)
            .background(AppTheme.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    @ViewBuilder
    private var bottomInputView: some View {
        Group {
            if let mcqState = viewModel.pendingMCQSelection {
                switch mcqState {
                case .optionSelected(let messageId, let option):
                    MCQConfirmBar(
                        onConfirm: { viewModel.confirmMCQSelection(messageId: messageId, option: option) },
                        onCancel: { viewModel.cancelMCQSelection() }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                case .customInputActive(let messageId):
                    MCQCustomInputBar(
                        text: $viewModel.customAnswerText,
                        onSubmit: { viewModel.confirmCustomAnswer(messageId: messageId) },
                        onCancel: { viewModel.cancelMCQSelection() }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            } else {
                ChatInputView(text: $viewModel.inputText) {
                    viewModel.sendMessage()
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.hasPendingMCQ)
    }

    // MARK: - Message View Builder

    @ViewBuilder
    private func messageView(for message: Message) -> some View {
        if let richContent = message.richContent {
            switch richContent {
            case .mcqQuestion(let question):
                MCQQuestionView(
                    question: question,
                    onOptionSelected: { option in
                        viewModel.handleMCQOptionSelected(option, messageId: message.id)
                    },
                    onCustomInputRequested: {
                        viewModel.handleCustomInputRequested(messageId: message.id)
                    }
                )
            case .codeDiff(let diff):
                CodeDiffView(
                    diff: Binding(
                        get: { diff },
                        set: { newDiff in
                            viewModel.updateCodeDiff(newDiff, for: message.id)
                        }
                    )
                )
            case .toolUsage(let state):
                ToolUsageIndicatorView(toolState: state)
            case .text:
                MessageBubbleView(message: message)
            }
        } else {
            MessageBubbleView(message: message)
        }
    }
}

// MARK: - Suggested Prompt Button

struct SuggestedPromptButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, AppTheme.spacingM)
                .padding(.vertical, AppTheme.spacingS)
                .frame(maxWidth: .infinity)
                .background(AppTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        }
    }
}

// MARK: - Typing Dot

struct TypingDot: View {
    let delay: Double
    let index: Int

    @State private var isAnimating = false

    private var baseSize: CGFloat {
        switch index {
        case 0: return 7
        case 1: return 8
        case 2: return 7.5
        default: return 8
        }
    }

    var body: some View {
        Circle()
            .fill(
                isAnimating
                    ? AppTheme.accent.opacity(0.8)
                    : AppTheme.textSecondary.opacity(0.5)
            )
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(isAnimating ? 1.2 : 0.6)
            .offset(y: isAnimating ? -3 : 2)
            .animation(
                .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

#Preview("With Messages") {
    NavigationStack {
        ChatView(chat: MockData.chats[0])
    }
    .tint(AppTheme.accent)
}

#Preview("New Chat") {
    NavigationStack {
        ChatView(chat: nil, project: MockData.projects[0])
    }
    .tint(AppTheme.accent)
}
