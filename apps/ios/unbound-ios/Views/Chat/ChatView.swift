import SwiftUI

/// State for pending MCQ selection
enum MCQSelectionState: Equatable {
    case optionSelected(messageId: UUID, option: MCQQuestion.MCQOption)
    case customInputActive(messageId: UUID)
}

struct ChatView: View {
    let chat: Chat?
    var project: Project? = nil

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var showDynamicIsland = false
    @State private var sessionManager = ActiveSessionManager()

    // Simulation state
    @State private var isFirstMessage = true
    @State private var currentToolState: ToolUsageState?
    @State private var completedTools: [ToolUsageState] = []
    @State private var pendingMCQId: UUID?
    @State private var simulationDiffs: [CodeDiff] = []

    // MCQ selection state
    @State private var pendingMCQSelection: MCQSelectionState?
    @State private var customAnswerText = ""

    private var chatTitle: String {
        chat?.title ?? "New Chat"
    }

    private var hasGeneratingSessions: Bool {
        sessionManager.sessions.contains { $0.status == .generating || $0.status == .reviewing }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.spacingM) {
                        if messages.isEmpty {
                            welcomeView
                                .padding(.top, 60)
                        } else {
                            ForEach(messages) { message in
                                messageView(for: message)
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.95).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }

                            // Live tool usage indicator with history
                            if !completedTools.isEmpty || currentToolState != nil {
                                ToolHistoryStackView(
                                    completedTools: completedTools,
                                    currentTool: currentToolState
                                )
                                .id("toolUsage")
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }

                            if isTyping {
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
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: isTyping) { _, newValue in
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
                    if sessionManager.hasActiveSessions {
                        DynamicIslandButton(
                            activeCount: sessionManager.sessions.count,
                            hasGenerating: hasGeneratingSessions
                        ) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                showDynamicIsland = true
                            }
                        }
                    }

                    GitActionsMenu(
                        onCreatePR: { handleGitAction("Creating PR...") },
                        onPushChanges: { handleGitAction("Pushing changes...") },
                        onViewFullDiff: { handleGitAction("Loading diff...") },
                        onCopyChanges: { handleGitAction("Copied to clipboard") },
                        onCommit: { handleGitAction("Committing changes...") }
                    )
                }
            }
        }
        .dynamicIslandOverlay(
            isExpanded: $showDynamicIsland,
            sessions: sessionManager.sessions
        ) { session in
            // Handle session tap - could navigate to that chat
            print("Navigate to: \(session.projectName) - \(session.chatTitle)")
            showDynamicIsland = false
        }
        .onAppear {
            if chat != nil {
                messages = MockData.messages
            }
        }
        .onDisappear {
            sessionManager.stopSimulation()
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
                    inputText = "Explain this codebase structure"
                }
                SuggestedPromptButton(text: "Help me debug an issue") {
                    inputText = "Help me debug an issue"
                }
                SuggestedPromptButton(text: "Suggest improvements") {
                    inputText = "Suggest improvements for this project"
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
            if let mcqState = pendingMCQSelection {
                switch mcqState {
                case .optionSelected(let messageId, let option):
                    MCQConfirmBar(
                        onConfirm: { confirmMCQSelection(messageId: messageId, option: option) },
                        onCancel: { cancelMCQSelection() }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                case .customInputActive(let messageId):
                    MCQCustomInputBar(
                        text: $customAnswerText,
                        onSubmit: { confirmCustomAnswer(messageId: messageId) },
                        onCancel: { cancelMCQSelection() }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            } else {
                ChatInputView(text: $inputText) {
                    sendMessage()
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pendingMCQSelection != nil)
    }

    private func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        inputText = ""

        // Add user message
        let userMessage = Message(
            id: UUID(),
            content: content,
            role: .user,
            timestamp: Date()
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages.append(userMessage)
        }

        // First message triggers the simulation flow
        if isFirstMessage {
            isFirstMessage = false
            triggerSimulationFlow()
        } else {
            // Normal response for subsequent messages
            simulateNormalResponse()
        }
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
                        handleMCQOptionSelected(option, messageId: message.id)
                    },
                    onCustomInputRequested: {
                        handleCustomInputRequested(messageId: message.id)
                    }
                )
            case .codeDiff(let diff):
                CodeDiffView(
                    diff: Binding(
                        get: { diff },
                        set: { newDiff in
                            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                                messages[index].richContent = .codeDiff(newDiff)
                            }
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

    // MARK: - Simulation Flow

    private func triggerSimulationFlow() {
        isTyping = true

        Task {
            try? await Task.sleep(for: .seconds(1.0))

            await MainActor.run {
                isTyping = false

                // Show MCQ question
                let mcqId = UUID()
                pendingMCQId = mcqId

                let mcqQuestion = MCQQuestion(
                    id: mcqId,
                    question: "How would you like me to implement this feature?",
                    options: [
                        MCQQuestion.MCQOption(
                            label: "Add to existing file",
                            description: "Modify ChatView.swift with new components",
                            icon: "doc.badge.plus"
                        ),
                        MCQQuestion.MCQOption(
                            label: "Create new files",
                            description: "Create separate component files",
                            icon: "folder.badge.plus"
                        ),
                        MCQQuestion.MCQOption(
                            label: "Let Claude decide",
                            description: "I'll analyze the codebase and choose the best approach",
                            icon: "brain.head.profile"
                        )
                    ]
                )

                let mcqMessage = Message(
                    id: UUID(),
                    content: "",
                    role: .assistant,
                    richContent: .mcqQuestion(mcqQuestion)
                )

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    messages.append(mcqMessage)
                }
            }
        }
    }

    // MARK: - MCQ Selection Handlers

    private func handleMCQOptionSelected(_ option: MCQQuestion.MCQOption, messageId: UUID) {
        // Update visual selection in the MCQ
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = option.id
                messages[index].richContent = .mcqQuestion(question)
            }
        }

        // Set pending state - show confirm bar at bottom
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = .optionSelected(messageId: messageId, option: option)
        }
    }

    private func handleCustomInputRequested(messageId: UUID) {
        // Update visual selection to show "Something else" selected
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = MCQQuestion.somethingElseOption.id
                messages[index].richContent = .mcqQuestion(question)
            }
        }

        // Set pending state - show custom input bar at bottom
        customAnswerText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = .customInputActive(messageId: messageId)
        }
    }

    private func confirmMCQSelection(messageId: UUID, option: MCQQuestion.MCQOption) {
        // Mark the MCQ as confirmed
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = option.id
                question.isConfirmed = true
                messages[index].richContent = .mcqQuestion(question)
            }
        }

        // Clear pending state
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = nil
        }

        // Start tool usage simulation
        Task {
            await simulateToolUsage()
        }
    }

    private func confirmCustomAnswer(messageId: UUID) {
        let answer = customAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        // Mark the MCQ as confirmed with custom answer
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = MCQQuestion.somethingElseOption.id
                question.customAnswer = answer
                question.isConfirmed = true
                messages[index].richContent = .mcqQuestion(question)
            }
        }

        // Clear pending state
        customAnswerText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = nil
        }

        // Start tool usage simulation
        Task {
            await simulateToolUsage()
        }
    }

    private func cancelMCQSelection() {
        // Clear the visual selection from the MCQ
        if case .optionSelected(let messageId, _) = pendingMCQSelection {
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                if case .mcqQuestion(var question) = messages[index].richContent {
                    question.selectedOptionId = nil
                    messages[index].richContent = .mcqQuestion(question)
                }
            }
        } else if case .customInputActive(let messageId) = pendingMCQSelection {
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                if case .mcqQuestion(var question) = messages[index].richContent {
                    question.selectedOptionId = nil
                    messages[index].richContent = .mcqQuestion(question)
                }
            }
        }

        // Clear pending state
        customAnswerText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = nil
        }
    }

    private func simulateToolUsage() async {
        // Clear any previous tool history
        await MainActor.run {
            completedTools = []
        }

        let toolSteps: [(String, String, TimeInterval)] = [
            ("Read", "Reading ChatView.swift", 0.8),
            ("Glob", "Searching for related components", 1.0),
            ("Read", "Analyzing AppTheme.swift", 0.6),
            ("Write", "Generating new code", 1.5)
        ]

        for (tool, status, duration) in toolSteps {
            let toolState = ToolUsageState(
                toolName: tool,
                statusText: status,
                isActive: true
            )

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentToolState = toolState
                }
            }

            try? await Task.sleep(for: .seconds(duration))

            // Mark as completed and add to history
            await MainActor.run {
                var completedTool = toolState
                completedTool.isActive = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    completedTools.append(completedTool)
                }
            }
        }

        // Clear tool state and show diff
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentToolState = nil
                completedTools = [] // Clear history when done
            }
        }

        try? await Task.sleep(for: .seconds(0.3))

        await showCodeDiff()
    }

    private func showCodeDiff() async {
        await MainActor.run {
            let diff = CodeDiff(
                filename: "Views/Chat/Components/NewFeatureView.swift",
                language: "swift",
                hunks: [
                    CodeDiff.DiffHunk(
                        header: "@@ -0,0 +1,28 @@",
                        lines: [
                            CodeDiff.DiffLine(content: "import SwiftUI", type: .addition, lineNumber: 1),
                            CodeDiff.DiffLine(content: "", type: .addition, lineNumber: 2),
                            CodeDiff.DiffLine(content: "struct NewFeatureView: View {", type: .addition, lineNumber: 3),
                            CodeDiff.DiffLine(content: "    @State private var isEnabled = false", type: .addition, lineNumber: 4),
                            CodeDiff.DiffLine(content: "", type: .addition, lineNumber: 5),
                            CodeDiff.DiffLine(content: "    var body: some View {", type: .addition, lineNumber: 6),
                            CodeDiff.DiffLine(content: "        VStack(spacing: AppTheme.spacingM) {", type: .addition, lineNumber: 7),
                            CodeDiff.DiffLine(content: "            Text(\"New Feature\")", type: .addition, lineNumber: 8),
                            CodeDiff.DiffLine(content: "                .font(.headline)", type: .addition, lineNumber: 9),
                            CodeDiff.DiffLine(content: "                .foregroundStyle(AppTheme.accent)", type: .addition, lineNumber: 10),
                            CodeDiff.DiffLine(content: "", type: .addition, lineNumber: 11),
                            CodeDiff.DiffLine(content: "            Toggle(\"Enable\", isOn: $isEnabled)", type: .addition, lineNumber: 12),
                            CodeDiff.DiffLine(content: "                .tint(AppTheme.accent)", type: .addition, lineNumber: 13),
                            CodeDiff.DiffLine(content: "        }", type: .addition, lineNumber: 14),
                            CodeDiff.DiffLine(content: "        .padding()", type: .addition, lineNumber: 15),
                            CodeDiff.DiffLine(content: "    }", type: .addition, lineNumber: 16),
                            CodeDiff.DiffLine(content: "}", type: .addition, lineNumber: 17),
                        ]
                    )
                ]
            )

            let responseMessage = Message(
                id: UUID(),
                content: "I've created the new component. Here's the diff:",
                role: .assistant
            )

            let diffMessage = Message(
                id: UUID(),
                content: "",
                role: .assistant,
                richContent: .codeDiff(diff)
            )

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                messages.append(responseMessage)
            }

            // Slight delay before showing diff
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    messages.append(diffMessage)
                }
            }
        }
    }

    private func simulateNormalResponse() {
        isTyping = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))

            let responses = [
                "I'll help you with that! Let me analyze the code and provide some suggestions.",
                "That's a great question. Here's what I found after reviewing the project structure...",
                "I understand what you're looking for. Let me break this down step by step.",
                "Based on the codebase, here's my recommendation for how to approach this..."
            ]

            let assistantMessage = Message(
                id: UUID(),
                content: responses.randomElement() ?? responses[0],
                role: .assistant
            )

            await MainActor.run {
                isTyping = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    messages.append(assistantMessage)
                }
            }
        }
    }

    private func handleGitAction(_ action: String) {
        let feedbackMessage = Message(
            id: UUID(),
            content: action,
            role: .system
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages.append(feedbackMessage)
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
