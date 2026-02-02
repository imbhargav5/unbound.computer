//
//  ChatPanel.swift
//  unbound-macos
//
//  Shadcn-styled chat panel with Claude CLI integration.
//  Works with a single Session (= Claude conversation).
//  Reads state from SessionLiveState via SessionStateManager,
//  enabling instant session switching and background streaming.
//

import SwiftUI
import Logging

private let logger = Logger(label: "app.ui.chat")

struct ChatPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    let session: Session?
    let repository: Repository?
    @Binding var chatInput: String
    @Binding var selectedModel: AIModel
    @Binding var selectedThinkMode: ThinkMode
    @Binding var isPlanMode: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// The live state for the current session (nil if no session selected)
    private var liveState: SessionLiveState? {
        guard let session else { return nil }
        return appState.sessionStateManager.state(for: session.id)
    }

    /// Workspace path validation result
    private enum WorkspacePathResult {
        case valid(String)
        case noSession
        case noRepository
        case pathNotFound(String)
    }

    /// Validate and determine the working directory for Claude CLI
    private var workspacePathResult: WorkspacePathResult {
        guard let session = session else { return .noSession }

        // If session is a worktree, use its worktree path
        if session.isWorktree, let worktreePath = session.worktreePath {
            guard FileManager.default.fileExists(atPath: worktreePath) else {
                return .pathNotFound(worktreePath)
            }
            return .valid(worktreePath)
        }

        // Otherwise use the repository path
        guard let path = repository?.path else { return .noRepository }
        guard FileManager.default.fileExists(atPath: path) else {
            return .pathNotFound(path)
        }
        return .valid(path)
    }

    /// Determine the working directory for Claude CLI (nil if invalid)
    private var workspacePath: String? {
        if case .valid(let path) = workspacePathResult {
            return path
        }
        return nil
    }

    /// Messages from live state
    private var messages: [ChatMessage] {
        liveState?.messages ?? []
    }

    /// Tool history from live state
    private var toolHistory: [ToolHistoryEntry] {
        liveState?.toolHistory ?? []
    }

    /// Currently active sub-agent (if any)
    private var activeSubAgent: ActiveSubAgent? {
        liveState?.activeSubAgent
    }

    /// Currently active standalone tools (not in a sub-agent)
    private var activeTools: [ActiveTool] {
        liveState?.activeTools ?? []
    }

    /// Whether there's any active tool state to display
    private var hasActiveToolState: Bool {
        activeSubAgent != nil || !activeTools.isEmpty || !toolHistory.isEmpty
    }

    /// Coalesced scroll identity - combines factors that should trigger auto-scroll
    /// Using a single hash prevents multiple scroll operations per update
    private var scrollIdentity: Int {
        var hasher = Hasher()
        hasher.combine(messages.count)
        hasher.combine(toolHistory.count)
        hasher.combine(activeSubAgent?.childTools.count ?? 0)
        hasher.combine(activeTools.count)
        if let last = messages.last {
            hasher.combine(last.content.count)
            // Include text length for smooth streaming scroll
            if case .text(let textContent) = last.content.last {
                hasher.combine(textContent.text.count)
            }
        }
        return hasher.finalize()
    }

    /// Loading state from live state
    private var isLoadingMessages: Bool {
        liveState?.isLoadingMessages ?? false
    }

    /// Check if Claude is currently running (streaming response)
    var isSessionStreaming: Bool {
        liveState?.claudeRunning ?? false
    }

    /// Binding for error alert presentation
    private var showErrorAlertBinding: Binding<Bool> {
        Binding(
            get: {
                liveState?.showErrorAlert ?? false
            },
            set: { _ in
                liveState?.dismissErrorAlert()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with project name
            ChatHeader(projectName: repository?.name ?? "No Repository")

            ShadcnDivider()

            // Chat content
            VStack(spacing: 0) {
                if let session = session {
                    if isLoadingMessages {
                        ProgressView("Loading messages...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if messages.isEmpty && !hasActiveToolState {
                        switch workspacePathResult {
                        case .noRepository:
                            // No workspace selected
                            NoWorkspaceSelectedView()
                        case .pathNotFound(let path):
                            // Path doesn't exist on disk
                            WorkspacePathNotFoundView(path: path)
                        case .valid, .noSession:
                            // Welcome view for empty chat
                            WelcomeChatView(
                                repoPath: repository?.name ?? "repository",
                                tip: FakeData.tipMessage
                            )
                        }
                        Spacer()
                    } else {
                        // Messages list with interleaved tool history
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                        ChatMessageView(
                                            message: message,
                                            onQuestionSubmit: handleQuestionSubmit
                                        )
                                        .id(message.id)

                                        // Render tool history entries that belong after this message
                                        ForEach(toolHistory.filter { $0.afterMessageIndex == index }) { entry in
                                            ToolHistoryEntryView(entry: entry)
                                        }
                                    }

                                    // Render active sub-agent (if running)
                                    if let subAgent = activeSubAgent {
                                        ActiveSubAgentView(subAgent: subAgent)
                                            .padding(.horizontal, Spacing.lg)
                                            .padding(.vertical, Spacing.sm)
                                    }

                                    // Render active standalone tools (if no sub-agent is running)
                                    if activeSubAgent == nil && !activeTools.isEmpty {
                                        ActiveToolsView(tools: activeTools)
                                            .padding(.horizontal, Spacing.lg)
                                            .padding(.vertical, Spacing.sm)
                                    }

                                    // Invisible scroll anchor at bottom for reliable scrolling
                                    Color.clear.frame(height: 1).id("bottomAnchor")
                                }
                            }
                            .onChange(of: scrollIdentity) { _, _ in
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                        }
                    }

                    // Input field at bottom
                    ChatInputField(
                        text: $chatInput,
                        selectedModel: $selectedModel,
                        selectedThinkMode: $selectedThinkMode,
                        isPlanMode: $isPlanMode,
                        isStreaming: isSessionStreaming,
                        onSend: sendMessage,
                        onCancel: cancelStream
                    )
                    .padding(Spacing.compact)
                    .disabled(workspacePath == nil)
                } else {
                    // No session selected
                    ContentUnavailableView(
                        "No Chat Selected",
                        systemImage: "message",
                        description: Text("Select a session or create a new one")
                    )
                }
            }
            .background(colors.background)

            ShadcnDivider()

            // Footer (empty, 20px height)
            Color.clear
                .frame(height: 20)
                .background(colors.card)
        }
        .task(id: session?.id) {
            if let state = liveState {
                await state.activate()
            }
        }
        .alert(
            liveState?.errorAlertTitle ?? "Error",
            isPresented: showErrorAlertBinding
        ) {
            Button("OK", role: .cancel) {
                liveState?.dismissErrorAlert()
            }
        } message: {
            Text(liveState?.errorAlertMessage ?? "An unknown error occurred")
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        logger.debug("sendMessage called, session=\(session?.id.uuidString ?? "nil"), path=\(workspacePath ?? "nil")")

        guard let session = session else {
            logger.warning("sendMessage: session is nil")
            return
        }
        guard let path = workspacePath else {
            logger.warning("sendMessage: workspacePath is nil")
            return
        }
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let messageText = chatInput
        chatInput = ""

        Task {
            await liveState?.sendMessage(
                messageText,
                session: session,
                workspacePath: path,
                modelIdentifier: selectedModel.modelIdentifier
            )
        }
    }

    private func cancelStream() {
        liveState?.cancelStream()
    }

    private func handleQuestionSubmit(_ question: AskUserQuestion) {
        // Build the response from selected options and/or text response
        var responseParts: [String] = []

        // Add selected options
        if !question.selectedOptions.isEmpty {
            responseParts.append(contentsOf: question.selectedOptions.sorted())
        }

        // Add text response if present
        if let textResponse = question.textResponse, !textResponse.isEmpty {
            responseParts.append(textResponse)
        }

        // Send to daemon if we have a response
        let response = responseParts.joined(separator: ", ")
        if !response.isEmpty {
            liveState?.respondToPrompt(response)
        }
    }
}

#Preview {
    ChatPanel(
        session: FakeData.sessions.first,
        repository: nil,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false)
    )
    .environment(AppState())
    .frame(width: 550, height: 600)
}
