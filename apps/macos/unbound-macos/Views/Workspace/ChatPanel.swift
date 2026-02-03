//
//  ChatPanel.swift
//  unbound-macos
//
//  Shadcn-styled chat panel with Claude CLI integration.
//  Split into two columns: chat on left, file editor on right.
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

    // File editor state - multiple open files with tabs
    @State private var openFiles: [OpenFile] = []
    @State private var selectedFileId: UUID?

    // Footer panel state
    @State private var selectedTerminalTab: TerminalTab = .terminal
    @State private var isFooterExpanded: Bool = false
    @State private var footerHeight: CGFloat = 0
    @State private var footerDragStartHeight: CGFloat = 0

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private enum FooterConstants {
        static let barHeight: CGFloat = 32
        static let handleHeight: CGFloat = 16
        static let minExpandedHeight: CGFloat = 160
        static let defaultExpandedRatio: CGFloat = 0.4
        static let maxExpandedRatio: CGFloat = 0.8
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
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                HSplitView {
                    // Left side - Chat conversation
                    chatColumn

                    // Right side - File editor
                    fileEditorColumn
                }
                .padding(.bottom, FooterConstants.barHeight)

                footerPanel(availableHeight: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Chat Column

    private var chatColumn: some View {
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
        }
        .frame(minWidth: 300)
    }

    /// Currently selected file for display
    private var selectedFile: OpenFile? {
        if let id = selectedFileId {
            return openFiles.first { $0.id == id }
        }
        return openFiles.first
    }

    // MARK: - File Editor Column

    private var fileEditorColumn: some View {
        VStack(spacing: 0) {
            // Editor header with file tabs
            FileEditorTabBar(
                files: openFiles,
                selectedFileId: selectedFileId ?? openFiles.first?.id,
                onSelectFile: { id in
                    selectedFileId = id
                },
                onCloseFile: { id in
                    closeFile(id: id)
                }
            )

            ShadcnDivider()

            // Editor content
            if let file = selectedFile {
                FileEditorView(filePath: file.path)
            } else {
                // No file open
                VStack(spacing: Spacing.md) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(colors.mutedForeground)

                    Text("No file open")
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)

                    Text("Select a file from the chat or file tree")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colors.background)
            }

        }
        .frame(minWidth: 300)
    }

    // MARK: - Footer Panel

    private func footerPanel(availableHeight: CGFloat) -> some View {
        let expandedHeight = clampedFooterHeight(
            footerHeight == 0 ? defaultFooterHeight(availableHeight) : footerHeight,
            availableHeight: availableHeight
        )
        let panelHeight = isFooterExpanded ? expandedHeight : FooterConstants.barHeight

        return VStack(spacing: 0) {
            if isFooterExpanded {
                footerHandle(availableHeight: availableHeight)
                ShadcnDivider()
            }

            footerTabBar(availableHeight: availableHeight)

            if isFooterExpanded {
                ShadcnDivider()

                footerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(colors.card)
            }
        }
        .frame(height: panelHeight)
        .frame(maxWidth: .infinity)
        .background(colors.card)
        .overlay(alignment: .top) {
            ShadcnDivider()
        }
        .onChange(of: availableHeight) { _, newHeight in
            guard isFooterExpanded else { return }
            footerHeight = clampedFooterHeight(
                footerHeight == 0 ? defaultFooterHeight(newHeight) : footerHeight,
                availableHeight: newHeight
            )
        }
    }

    private func footerTabBar(availableHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(TerminalTab.allCases) { tab in
                Button {
                    handleFooterTabTap(tab, availableHeight: availableHeight)
                } label: {
                    Text(tab.rawValue)
                        .font(Typography.bodySmall)
                        .foregroundStyle(selectedTerminalTab == tab ? colors.foreground : colors.mutedForeground)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: FooterConstants.barHeight)
        .background(colors.card)
    }

    private func footerHandle(availableHeight: CGFloat) -> some View {
        Capsule()
            .fill(colors.mutedForeground.opacity(0.4))
            .frame(width: 32, height: 4)
            .frame(maxWidth: .infinity, maxHeight: FooterConstants.handleHeight)
            .contentShape(Rectangle())
            .gesture(resizeGesture(availableHeight: availableHeight))
    }

    private var footerContent: some View {
        switch selectedTerminalTab {
        case .terminal:
            terminalFooterContent
        case .output:
            footerPlaceholder("No output yet")
        case .problems:
            footerPlaceholder("No problems detected")
        case .scripts:
            footerPlaceholder("No scripts configured")
        }
    }

    private var terminalFooterContent: some View {
        Group {
            if let path = workspacePath {
                TerminalContainer(workingDirectory: path)
            } else {
                Text("No workspace selected")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Spacing.md)
            }
        }
    }

    private func footerPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(Typography.bodySmall)
            .foregroundStyle(colors.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
    }

    private func handleFooterTabTap(_ tab: TerminalTab, availableHeight: CGFloat) {
        if tab == selectedTerminalTab {
            if isFooterExpanded {
                collapseFooter()
            } else {
                expandFooter(availableHeight: availableHeight)
            }
            return
        }

        selectedTerminalTab = tab

        if !isFooterExpanded {
            expandFooter(availableHeight: availableHeight)
        }
    }

    private func expandFooter(availableHeight: CGFloat) {
        let targetHeight = footerHeight == 0 ? defaultFooterHeight(availableHeight) : footerHeight
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isFooterExpanded = true
            footerHeight = clampedFooterHeight(targetHeight, availableHeight: availableHeight)
        }
    }

    private func collapseFooter() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isFooterExpanded = false
        }
    }

    private func defaultFooterHeight(_ availableHeight: CGFloat) -> CGFloat {
        max(FooterConstants.minExpandedHeight, availableHeight * FooterConstants.defaultExpandedRatio)
    }

    private func maxFooterHeight(_ availableHeight: CGFloat) -> CGFloat {
        max(FooterConstants.minExpandedHeight, availableHeight * FooterConstants.maxExpandedRatio)
    }

    private func clampedFooterHeight(_ proposed: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(max(proposed, FooterConstants.minExpandedHeight), maxFooterHeight(availableHeight))
    }

    private func resizeGesture(availableHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard isFooterExpanded else { return }

                if footerDragStartHeight == 0 {
                    footerDragStartHeight = footerHeight == 0 ? defaultFooterHeight(availableHeight) : footerHeight
                }

                let proposedHeight = footerDragStartHeight - value.translation.height
                footerHeight = clampedFooterHeight(proposedHeight, availableHeight: availableHeight)
            }
            .onEnded { _ in
                footerDragStartHeight = 0
            }
    }

    private func closeFile(id: UUID) {
        // If closing the selected file, select another one
        if selectedFileId == id {
            if let index = openFiles.firstIndex(where: { $0.id == id }) {
                // Try to select the next file, or previous if at end
                if index < openFiles.count - 1 {
                    selectedFileId = openFiles[index + 1].id
                } else if index > 0 {
                    selectedFileId = openFiles[index - 1].id
                } else {
                    selectedFileId = nil
                }
            }
        }
        openFiles.removeAll { $0.id == id }
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

// MARK: - Open File Model

struct OpenFile: Identifiable {
    let id = UUID()
    let path: String

    var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }
}

// MARK: - File Editor Tab Bar

struct FileEditorTabBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let files: [OpenFile]
    let selectedFileId: UUID?
    var onSelectFile: (UUID) -> Void
    var onCloseFile: (UUID) -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            if files.isEmpty {
                Text("Editor")
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.mutedForeground)
                    .padding(.horizontal, Spacing.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(files) { file in
                            FileTab(
                                file: file,
                                isSelected: selectedFileId == file.id,
                                onSelect: { onSelectFile(file.id) },
                                onClose: { onCloseFile(file.id) }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: 40)
        .background(colors.card)
    }
}

// MARK: - File Tab (Pill)

struct FileTab: View {
    @Environment(\.colorScheme) private var colorScheme

    let file: OpenFile
    let isSelected: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isHovered: Bool = false
    @State private var isCloseHovered: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.xs) {
                // File icon
                Image(systemName: fileIcon(for: file.fileExtension))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)

                // File name
                Text(file.filename)
                    .font(Typography.caption)
                    .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)
                    .lineLimit(1)

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(isCloseHovered ? colors.foreground : colors.mutedForeground)
                        .frame(width: 14, height: 14)
                        .background(isCloseHovered ? colors.muted : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isCloseHovered = hovering
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected ? colors.muted : (isHovered ? colors.muted.opacity(0.5) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(isSelected ? colors.border : Color.clear, lineWidth: BorderWidth.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func fileIcon(for ext: String) -> String {
        switch ext {
        case "swift": return "swift"
        case "js", "javascript": return "curlybraces"
        case "ts", "typescript": return "curlybraces"
        case "py", "python": return "chevron.left.forwardslash.chevron.right"
        case "rs", "rust": return "gearshape.2"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown": return "doc.richtext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "list.bullet.indent"
        default: return "doc.text"
        }
    }
}

// MARK: - File Editor View

struct FileEditorView: View {
    @Environment(\.colorScheme) private var colorScheme

    let filePath: String

    @State private var fileContent: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var lines: [String] {
        fileContent.components(separatedBy: "\n")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading file...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(colors.destructive)
                    Text("Failed to load file")
                        .font(Typography.body)
                        .foregroundStyle(colors.foreground)
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        // Line numbers gutter
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                                Text("\(index + 1)")
                                    .font(.system(size: FontSize.sm, design: .monospaced))
                                    .foregroundStyle(colors.mutedForeground.opacity(0.5))
                                    .frame(height: 20)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                        .background(colors.card.opacity(0.5))

                        // Code content
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: FontSize.sm, design: .monospaced))
                                    .foregroundStyle(colors.foreground)
                                    .frame(height: 20, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .background(colors.background)
        .task(id: filePath) {
            await loadFile()
        }
    }

    private func loadFile() async {
        isLoading = true
        errorMessage = nil

        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            fileContent = content
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
    .frame(width: 900, height: 600)
}
