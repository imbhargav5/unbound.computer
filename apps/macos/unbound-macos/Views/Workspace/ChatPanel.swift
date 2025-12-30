//
//  ChatPanel.swift
//  unbound-macos
//
//  Shadcn-styled chat panel with Claude CLI integration
//

import SwiftUI

struct ChatPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @Binding var tabs: [ChatTab]
    @Binding var selectedTabId: UUID?
    @Binding var chatInput: String
    @Binding var selectedModel: AIModel
    let currentRepo: String
    let workspacePath: String?

    @State private var streamingTask: Task<Void, Never>?
    @State private var currentStreamingMessageId: UUID?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var selectedTab: ChatTab? {
        tabs.first { $0.id == selectedTabId }
    }

    /// Check if the current tab has any streaming messages
    var isCurrentTabStreaming: Bool {
        selectedTab?.messages.contains { $0.isStreaming } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with project name
            ChatHeader(projectName: currentRepo) {
                // Open action
            }

            ShadcnDivider()

            // Tab bar
            TabBar(
                tabs: $tabs,
                selectedTabId: $selectedTabId,
                onAddTab: addNewTab
            )

            ShadcnDivider()

            // Chat content
            VStack(spacing: 0) {
                if let tab = selectedTab {
                    if tab.messages.isEmpty {
                        if workspacePath == nil {
                            // No workspace selected
                            NoWorkspaceSelectedView()
                        } else {
                            // Welcome view for empty chat
                            WelcomeChatView(
                                repoPath: currentRepo,
                                tip: FakeData.tipMessage
                            )
                        }

                        Spacer()
                    } else {
                        // Messages list
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(tab.messages) { message in
                                        ChatMessageView(
                                            message: message,
                                            onQuestionSubmit: handleQuestionSubmit
                                        )
                                        .id(message.id)
                                        ShadcnDivider()
                                            .padding(.horizontal, Spacing.lg)
                                    }
                                }
                            }
                            .onChange(of: tab.messages.count) { _, _ in
                                if let lastMessage = tab.messages.last {
                                    withAnimation {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // No tab selected
                    ContentUnavailableView(
                        "No Chat Selected",
                        systemImage: "message",
                        description: Text("Select a tab or create a new one")
                    )
                }

                // Cancel button if current tab is streaming
                if isCurrentTabStreaming {
                    Button {
                        cancelStream()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Cancel")
                                .font(Typography.bodySmall)
                        }
                        .foregroundStyle(colors.destructive)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, Spacing.sm)
                }

                // Input field at bottom
                ChatInputField(
                    text: $chatInput,
                    selectedModel: $selectedModel,
                    onSend: sendMessage
                )
                .padding(Spacing.lg)
                .disabled(isCurrentTabStreaming || workspacePath == nil)
            }
            .background(colors.background)
        }
    }

    private func addNewTab() {
        let newTab = ChatTab(title: "Untitled")
        tabs.append(newTab)
        selectedTabId = newTab.id
    }

    private func sendMessage() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let tabIndex = tabs.firstIndex(where: { $0.id == selectedTabId }) else {
            return
        }

        let messageText = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add user message
        let userMessage = ChatMessage(role: .user, text: messageText)
        tabs[tabIndex].messages.append(userMessage)

        // Clear input
        chatInput = ""

        // Check if Claude is installed and we have a workspace path
        guard appState.claudeService.isClaudeInstalled() else {
            let errorMessage = ChatMessage(
                role: .assistant,
                content: [.error(ErrorContent(
                    message: "Claude CLI not installed",
                    details: "Please install Claude CLI to use this feature."
                ))]
            )
            tabs[tabIndex].messages.append(errorMessage)
            return
        }

        guard let path = workspacePath else {
            // Fallback to simulated response if no workspace path
            simulateResponse(messageText: messageText, tabIndex: tabIndex)
            return
        }

        // Create streaming assistant message
        let assistantMessageId = UUID()
        let assistantMessage = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: [],
            isStreaming: true
        )
        tabs[tabIndex].messages.append(assistantMessage)
        currentStreamingMessageId = assistantMessageId

        // Start streaming - pass Claude session ID if we have one from previous conversation
        let claudeSessionId = tabs[tabIndex].claudeSessionId
        let modelId = selectedModel.modelIdentifier
        streamingTask = Task {
            await streamClaudeResponse(message: messageText, path: path, tabIndex: tabIndex, messageId: assistantMessageId, claudeSessionId: claudeSessionId, modelIdentifier: modelId)
        }
    }

    private func streamClaudeResponse(message: String, path: String, tabIndex: Int, messageId: UUID, claudeSessionId: String?, modelIdentifier: String?) async {
        let stream = appState.claudeService.sendMessage(message, workingDirectory: path, claudeSessionId: claudeSessionId, modelIdentifier: modelIdentifier)

        do {
            for try await output in stream {
                await MainActor.run {
                    guard let msgIndex = tabs[tabIndex].messages.firstIndex(where: { $0.id == messageId }) else {
                        return
                    }

                    switch output {
                    case .text(let text):
                        // Append text to the last text content or create new
                        if case .text(var textContent) = tabs[tabIndex].messages[msgIndex].content.last {
                            tabs[tabIndex].messages[msgIndex].content.removeLast()
                            textContent = TextContent(id: textContent.id, text: textContent.text + text)
                            tabs[tabIndex].messages[msgIndex].content.append(.text(textContent))
                        } else {
                            tabs[tabIndex].messages[msgIndex].content.append(.text(TextContent(text: text)))
                        }

                    case .structuredBlock(let content):
                        tabs[tabIndex].messages[msgIndex].content.append(content)

                    case .prompt(let question):
                        tabs[tabIndex].messages[msgIndex].content.append(.askUserQuestion(question))

                    case .sessionStarted(let sessionId):
                        // Store the session ID in the tab for future conversation resumption
                        tabs[tabIndex].claudeSessionId = sessionId

                    case .toolResult(let toolUseId, let output):
                        // Find and update the matching tool use by toolUseId
                        for (contentIndex, content) in tabs[tabIndex].messages[msgIndex].content.enumerated() {
                            if case .toolUse(var toolUse) = content,
                               toolUse.toolUseId == toolUseId {
                                toolUse.output = output
                                toolUse.status = .completed
                                tabs[tabIndex].messages[msgIndex].content[contentIndex] = .toolUse(toolUse)
                                break
                            }
                        }

                    case .error(let errorText):
                        tabs[tabIndex].messages[msgIndex].content.append(.error(ErrorContent(message: errorText)))

                    case .complete:
                        tabs[tabIndex].messages[msgIndex].isStreaming = false
                    }
                }
            }
        } catch {
            await MainActor.run {
                if let msgIndex = tabs[tabIndex].messages.firstIndex(where: { $0.id == messageId }) {
                    tabs[tabIndex].messages[msgIndex].isStreaming = false
                    tabs[tabIndex].messages[msgIndex].content.append(.error(ErrorContent(
                        message: "Error",
                        details: error.localizedDescription
                    )))
                }
            }
        }

        // Always ensure streaming state is cleared
        await MainActor.run {
            if let msgIndex = tabs[tabIndex].messages.firstIndex(where: { $0.id == messageId }) {
                tabs[tabIndex].messages[msgIndex].isStreaming = false
            }
            currentStreamingMessageId = nil
            streamingTask = nil
        }
    }

    private func simulateResponse(messageText: String, tabIndex: Int) {
        // Fallback simulated response when no workspace
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let assistantMessage = ChatMessage(
                role: .assistant,
                text: "I understand you want to discuss '\(messageText)'. How can I help you with that?"
            )
            if let idx = tabs.firstIndex(where: { $0.id == selectedTabId }) {
                tabs[idx].messages.append(assistantMessage)
            }
        }
    }

    private func cancelStream() {
        streamingTask?.cancel()
        streamingTask = nil
        appState.claudeService.cancel()

        if let messageId = currentStreamingMessageId,
           let tabIndex = tabs.firstIndex(where: { $0.id == selectedTabId }),
           let msgIndex = tabs[tabIndex].messages.firstIndex(where: { $0.id == messageId }) {
            tabs[tabIndex].messages[msgIndex].isStreaming = false
            tabs[tabIndex].messages[msgIndex].content.append(.error(ErrorContent(message: "Cancelled")))
        }

        currentStreamingMessageId = nil
    }

    private func handleQuestionSubmit(_ question: AskUserQuestion) {
        // Format response based on selections
        var response = ""
        if !question.selectedOptions.isEmpty {
            let selectedLabels = question.options
                .filter { question.selectedOptions.contains($0.id) }
                .map { $0.label }
            response = selectedLabels.joined(separator: ", ")
        }
        if let text = question.textResponse, !text.isEmpty {
            if !response.isEmpty {
                response += ": "
            }
            response += text
        }

        // Send response to Claude
        do {
            try appState.claudeService.respondToPrompt(response)
        } catch {
            print("Failed to respond to prompt: \(error)")
        }
    }
}

#Preview {
    ChatPanel(
        tabs: .constant(FakeData.sampleChatTabs),
        selectedTabId: .constant(FakeData.sampleChatTabs.first?.id),
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        currentRepo: "otter",
        workspacePath: nil
    )
    .environment(AppState())
    .frame(width: 550, height: 600)
}
