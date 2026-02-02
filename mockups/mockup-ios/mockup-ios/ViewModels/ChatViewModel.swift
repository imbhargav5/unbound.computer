import Foundation
import SwiftUI

/// State for pending MCQ selection
enum MCQSelectionState: Equatable {
    case optionSelected(messageId: UUID, option: MCQQuestion.MCQOption)
    case customInputActive(messageId: UUID)
}

/// ViewModel for ChatView - manages all chat-related state and business logic
@Observable
final class ChatViewModel {
    // MARK: - Message State

    var messages: [Message] = []
    var inputText = ""
    var isTyping = false

    // MARK: - Session State

    var sessionManager = ActiveSessionManager()
    var showDynamicIsland = false

    // MARK: - Simulation State

    private(set) var isFirstMessage = true
    var currentToolState: ToolUsageState?
    var completedTools: [ToolUsageState] = []
    var simulationDiffs: [CodeDiff] = []

    // MARK: - MCQ State

    var pendingMCQId: UUID?
    var pendingMCQSelection: MCQSelectionState?
    var customAnswerText = ""

    // MARK: - Computed Properties

    var hasGeneratingSessions: Bool {
        sessionManager.sessions.contains { $0.status == .generating || $0.status == .reviewing }
    }

    var hasPendingMCQ: Bool {
        pendingMCQSelection != nil
    }

    // MARK: - Initialization

    init() {}

    func loadMessages(for chat: Chat?) {
        if chat != nil {
            messages = MockData.messages
        }
    }

    func cleanup() {
        sessionManager.stopSimulation()
    }

    // MARK: - Message Actions

    func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        inputText = ""

        let userMessage = Message(
            id: UUID(),
            content: content,
            role: .user,
            timestamp: Date()
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages.append(userMessage)
        }

        if isFirstMessage {
            isFirstMessage = false
            triggerSimulationFlow()
        } else {
            simulateNormalResponse()
        }
    }

    func handleGitAction(_ action: String) {
        let feedbackMessage = Message(
            id: UUID(),
            content: action,
            role: .system
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages.append(feedbackMessage)
        }
    }

    // MARK: - MCQ Handlers

    func handleMCQOptionSelected(_ option: MCQQuestion.MCQOption, messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = option.id
                messages[index].richContent = .mcqQuestion(question)
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = .optionSelected(messageId: messageId, option: option)
        }
    }

    func handleCustomInputRequested(messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = MCQQuestion.somethingElseOption.id
                messages[index].richContent = .mcqQuestion(question)
            }
        }

        customAnswerText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = .customInputActive(messageId: messageId)
        }
    }

    func confirmMCQSelection(messageId: UUID, option: MCQQuestion.MCQOption) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = option.id
                question.isConfirmed = true
                messages[index].richContent = .mcqQuestion(question)
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = nil
        }

        Task {
            await simulateToolUsage()
        }
    }

    func confirmCustomAnswer(messageId: UUID) {
        let answer = customAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = MCQQuestion.somethingElseOption.id
                question.customAnswer = answer
                question.isConfirmed = true
                messages[index].richContent = .mcqQuestion(question)
            }
        }

        customAnswerText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = nil
        }

        Task {
            await simulateToolUsage()
        }
    }

    func cancelMCQSelection() {
        if case .optionSelected(let messageId, _) = pendingMCQSelection {
            clearMCQSelection(for: messageId)
        } else if case .customInputActive(let messageId) = pendingMCQSelection {
            clearMCQSelection(for: messageId)
        }

        customAnswerText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingMCQSelection = nil
        }
    }

    private func clearMCQSelection(for messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            if case .mcqQuestion(var question) = messages[index].richContent {
                question.selectedOptionId = nil
                messages[index].richContent = .mcqQuestion(question)
            }
        }
    }

    // MARK: - Code Diff Handlers

    func updateCodeDiff(_ newDiff: CodeDiff, for messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].richContent = .codeDiff(newDiff)
        }
    }

    // MARK: - Simulation Flow

    private func triggerSimulationFlow() {
        isTyping = true

        Task {
            try? await Task.sleep(for: .seconds(1.0))

            await MainActor.run {
                isTyping = false

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

    private func simulateToolUsage() async {
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

            await MainActor.run {
                var completedTool = toolState
                completedTool.isActive = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    completedTools.append(completedTool)
                }
            }
        }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentToolState = nil
                completedTools = []
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.messages.append(diffMessage)
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
}
