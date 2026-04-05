//
//  ChatPanel.swift
//  unbound-macos
//
//  Shadcn-styled chat panel with Claude CLI integration.
//  Single-column chat view with messages and input.
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
    @Bindable var editorState: EditorState
    @Bindable var workspaceTabState: WorkspaceTabState
    @State private var conflictTabId: UUID?
    @State private var conflictRevision: DaemonFileRevision?
    @State private var showConflictDialog = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Currently selected editor tab
    private var selectedEditorTab: EditorTab? {
        guard case .editor(let id) = workspaceTabState.selection else { return nil }
        return editorState.tabs.first { $0.id == id }
    }

    private var selectedFileTab: EditorTab? {
        guard let tab = selectedEditorTab, tab.kind == .file else { return nil }
        return tab
    }

    private var activeTerminalTabId: UUID? {
        guard case .terminal(let tabId) = workspaceTabState.selection else { return nil }
        return tabId
    }

    private var agentRuns: [Session] {
        guard let agentId = session?.agentId else { return [] }
        return appState.sessionsForAgent(agentId)
    }

    private var repositoriesById: [UUID: Repository] {
        Dictionary(uniqueKeysWithValues: appState.repositories.map { ($0.id, $0) })
    }

    /// The live state for the current session (nil if no session selected)
    private var liveState: SessionLiveState? {
        guard let session else { return nil }
        // Read-only access in body; creation happens in .task to avoid mutating
        // observable state during a view update cycle.
        return appState.sessionStateManager.stateIfExists(for: session.id)
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
        let repositoryPath = repository?.path
            ?? appState.repositories.first(where: { $0.id == session.repositoryId })?.path
        guard let path = repositoryPath else { return .noRepository }
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

    private var timelineSnapshot: ChatTimelineSnapshot {
        liveState?.timelineSnapshot ?? .empty
    }

    private var renderedMessageCount: Int {
        timelineSnapshot.renderedMessageCount
    }

    private var timelineRowsAreEmpty: Bool {
        timelineSnapshot.isEmpty
    }

    /// Loading state from live state
    private var isLoadingMessages: Bool {
        liveState?.isLoadingMessages ?? false
    }

    private var canSendMessages: Bool {
        liveState?.canSendMessage ?? true
    }

    private var runtimeStatusSummary: (status: CodingSessionRuntimeStatus, errorMessage: String?)? {
        guard let liveState else { return nil }
        let status = liveState.codingSessionStatus
        let errorMessage = liveState.codingSessionErrorMessage
        if status == .idle && errorMessage == nil { return nil }
        return (status: status, errorMessage: errorMessage)
    }

    private var latestCompletionSummary: SessionCompletionSummary? {
        liveState?.latestCompletionSummary
    }

    /// Check if Claude is currently running (streaming response)
    var isSessionStreaming: Bool {
        guard let liveState else { return false }
        return liveState.claudeRunning || liveState.codingSessionStatus == .waiting
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

    private func runtimeStatusColor(for status: CodingSessionRuntimeStatus) -> Color {
        switch status {
        case .running:
            return colors.success
        case .idle, .notAvailable:
            return colors.mutedForeground
        case .waiting:
            return colors.warning
        case .error:
            return colors.destructive
        }
    }

    var body: some View {
        Group {
            switch workspaceTabState.selection {
            case .conversation:
                chatColumn
            case .agentRuns:
                agentRunsColumn
            case .editor:
                editorColumn
            case .terminal:
                terminalColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: session?.id) {
            guard let session else { return }
            await Task.yield()
            let state = appState.sessionStateManager.state(for: session.id)
            await state.activate()
        }
        .overlay {
            if showErrorAlertBinding.wrappedValue {
                ZStack {
                    Color(hex: "0D0D0D").opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            liveState?.dismissErrorAlert()
                        }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: IconSize.lg, weight: .semibold))
                                .foregroundStyle(colors.destructive)
                            Text(liveState?.errorAlertTitle ?? "Error")
                                .font(Typography.h4)
                                .foregroundStyle(colors.foreground)
                            Spacer()
                        }

                        Text(liveState?.errorAlertMessage ?? "An unknown error occurred")
                            .font(Typography.bodySmall)
                            .foregroundStyle(colors.mutedForeground)

                        HStack(spacing: Spacing.sm) {
                            Spacer()
                            Button("OK") {
                                liveState?.dismissErrorAlert()
                            }
                            .buttonPrimary(size: .sm)
                        }
                    }
                    .padding(Spacing.lg)
                    .frame(width: 360)
                    .background(colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .stroke(colors.border, lineWidth: BorderWidth.default)
                    )
                    .elevation(Elevation.lg)
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if showConflictDialog {
                ZStack {
                    Color(hex: "0D0D0D").opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            clearConflictState()
                        }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: IconSize.lg, weight: .semibold))
                                .foregroundStyle(colors.warning)
                            Text("File Changed on Disk")
                                .font(Typography.h4)
                                .foregroundStyle(colors.foreground)
                            Spacer()
                        }

                        if let revision = conflictRevision {
                            Text("Current revision token: \(revision.token)")
                                .font(Typography.bodySmall)
                                .foregroundStyle(colors.mutedForeground)
                        } else {
                            Text("The file was modified externally. Reload or overwrite your local edits.")
                                .font(Typography.bodySmall)
                                .foregroundStyle(colors.mutedForeground)
                        }

                        HStack(spacing: Spacing.sm) {
                            Spacer()
                            Button("Cancel") {
                                clearConflictState()
                            }
                            .buttonSecondary(size: .sm)

                            Button("Overwrite") {
                                guard let tabId = conflictTabId else { return }
                                Task {
                                    await overwriteAfterConflict(tabId: tabId)
                                }
                            }
                            .buttonDestructive(size: .sm)

                            Button("Reload") {
                                guard let tabId = conflictTabId else { return }
                                Task {
                                    await editorState.reloadFile(tabId: tabId, daemonClient: appState.daemonClient)
                                    clearConflictState()
                                }
                            }
                            .buttonPrimary(size: .sm)
                        }
                    }
                    .padding(Spacing.lg)
                    .frame(width: 400)
                    .background(colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .stroke(colors.border, lineWidth: BorderWidth.default)
                    )
                    .elevation(Elevation.lg)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Editor Column

    private var editorColumn: some View {
        editorContent
        .frame(minWidth: 300)
        .background(colors.editorBackground)
        .background {
            if selectedFileTab != nil {
                Button("Save") {
                    Task { await saveActiveFile() }
                }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
            }
        }
    }

    // MARK: - Editor Content

    @ViewBuilder
    private var editorContent: some View {
        if let tab = selectedEditorTab {
            switch tab.kind {
            case .file:
                FileEditorView(tab: tab, editorState: editorState)
            case .diff:
                DiffEditorView(
                    path: tab.path,
                    diffState: editorState.diffStates[tab.path]
                )
            }
        }
    }

    // MARK: - Chat Column

    private var chatColumn: some View {
        VStack(spacing: 0) {
            if session != nil {
                sessionHeaderCard
            }

            VStack(spacing: 0) {
                if let session = session {
                    if isLoadingMessages {
                        ProgressView("Loading messages...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if timelineRowsAreEmpty {
                        switch workspacePathResult {
                        case .noRepository:
                            NoWorkspaceSelectedView()
                        case .pathNotFound(let path):
                            WorkspacePathNotFoundView(path: path)
                        case .valid, .noSession:
                            WelcomeChatView(
                                repoPath: repository?.name
                                    ?? appState.repositories.first(where: { $0.id == session.repositoryId })?.name
                                    ?? "repository",
                                tip: FakeData.tipMessage
                            )
                            .onAppear {
                                liveState?.markSessionOpenVisibleReady(reason: "empty_state", isEmptyState: true)
                                liveState?.markMessageSendVisibleFeedback(reason: "empty_state")
                            }
                        }
                        Spacer()
                    } else {
                        ChatSnapshotScrollView(
                            snapshot: timelineSnapshot,
                            onQuestionSubmit: handleQuestionSubmit,
                            onInitialRenderComplete: {
                                liveState?.markSessionOpenVisibleReady(reason: "initial_render")
                            },
                            onLatestContentVisible: {
                                liveState?.markMessageSendVisibleFeedback(reason: "chat_content_visible")
                            },
                            header: { EmptyView() }
                        )
                        .id(session.id)
                    }

                    if let runtimeStatusSummary {
                        HStack(spacing: Spacing.sm) {
                            Circle()
                                .fill(runtimeStatusColor(for: runtimeStatusSummary.status))
                                .frame(width: 8, height: 8)

                            Text(runtimeStatusSummary.status.displayName)
                                .font(Typography.caption)
                                .foregroundStyle(runtimeStatusColor(for: runtimeStatusSummary.status))

                            if let errorMessage = runtimeStatusSummary.errorMessage {
                                Text(errorMessage)
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.destructive)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, Spacing.compact)
                        .padding(.top, Spacing.xs)
                        .onAppear {
                            liveState?.markMessageSendVisibleFeedback(reason: "runtime_status_visible")
                        }
                        .onChange(of: runtimeStatusSummary.status.rawValue) { _, _ in
                            liveState?.markMessageSendVisibleFeedback(reason: "runtime_status_visible")
                        }
                    }

                    ChatInputField(
                        text: $chatInput,
                        selectedModel: $selectedModel,
                        selectedThinkMode: $selectedThinkMode,
                        isPlanMode: $isPlanMode,
                        latestCompletionSummary: latestCompletionSummary,
                        isStreaming: isSessionStreaming,
                        onSend: sendMessage,
                        onCancel: cancelStream
                    )
                    .padding(Spacing.compact)
                    .disabled(workspacePath == nil || !canSendMessages)
                } else {
                    ContentUnavailableView(
                        "No Chat Selected",
                        systemImage: "message",
                        description: Text("Select a session or create a new one")
                    )
                }
            }
            .background(colors.chatBackground)
        }
        .frame(minWidth: 300)
    }

    @ViewBuilder
    private var agentRunsColumn: some View {
        if let session, session.agentId != nil {
            AgentRunsView(
                currentSession: session,
                runs: agentRuns,
                repositoriesById: repositoriesById,
                onSelectRun: handleRunSelection
            )
        } else {
            ContentUnavailableView(
                "No agent runs",
                systemImage: "clock.arrow.circlepath",
                description: Text("This session is not linked to a persisted agent.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.chatBackground)
        }
    }

    private var terminalColumn: some View {
        ZStack {
            ForEach(workspaceTabState.terminalTabs) { tab in
                TerminalContainer(tabId: tab.id, workingDirectory: tab.workingDirectory)
                    .opacity(activeTerminalTabId == tab.id ? 1 : 0)
                    .allowsHitTesting(activeTerminalTabId == tab.id)
            }

            if workspaceTabState.terminalTabs.isEmpty {
                ContentUnavailableView(
                    "No Terminal Tabs",
                    systemImage: "terminal",
                    description: Text("Use Control + ` or right-click a session to create one.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.chatBackground)
    }

    private var sessionHeaderCard: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(session?.displayTitle ?? "Session")
                    .font(Typography.bodyMedium)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)

                if let agentName = session?.agentName, !agentName.isEmpty {
                    Text(agentName)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                if let issueTitle = session?.displayIssueTitle {
                    Text(issueTitle)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                }

                Text(session?.id.uuidString.lowercased() ?? "")
                    .font(Typography.mono)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(alignment: .center, spacing: Spacing.sm) {
                if let agentId = session?.agentId {
                    Button("View Runs") {
                        workspaceTabState.openAgentRuns(
                            agentId: agentId,
                            title: session?.displayAgentName ?? "Runs"
                        )
                    }
                    .buttonOutline(size: .sm)
                }

                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text("Rendered")
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)
                    Text("\(renderedMessageCount)")
                        .font(Typography.captionMedium)
                        .foregroundStyle(colors.foreground)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: "1A1A1A"))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "2A2A2A"), lineWidth: BorderWidth.default)
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private func saveActiveFile() async {
        guard let tab = selectedFileTab else { return }
        await performSave(tabId: tab.id, forceOverwrite: false)
    }

    private func overwriteAfterConflict(tabId: UUID) async {
        await performSave(tabId: tabId, forceOverwrite: true)
        clearConflictState()
    }

    private func performSave(
        tabId: UUID,
        forceOverwrite: Bool
    ) async {
        do {
            let outcome = try await editorState.saveFile(
                tabId: tabId,
                daemonClient: appState.daemonClient,
                forceOverwrite: forceOverwrite
            )
            switch outcome {
            case .saved:
                break
            case .noChanges:
                break
            case .conflict(let currentRevision):
                conflictTabId = tabId
                conflictRevision = currentRevision
                showConflictDialog = true
            }
        } catch {
            logger.warning("Save failed: \(error.localizedDescription)")
        }
    }

    private func clearConflictState() {
        conflictTabId = nil
        conflictRevision = nil
        showConflictDialog = false
    }

    // MARK: - Chat Actions

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
                modelIdentifier: selectedModel.modelIdentifier,
                isPlanMode: isPlanMode
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

    private func handleRunSelection(_ run: Session) {
        let editorTabIds = editorState.tabs.map(\.id)
        workspaceTabState.closeAgentRuns(editorTabIds: editorTabIds)

        guard run.id != session?.id else {
            workspaceTabState.selectConversation()
            return
        }

        appState.selectSession(run.id, source: .agentRuns)
    }
}

// MARK: - File Editor Tab Bar

struct FileEditorTabBar<Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let files: [EditorTab]
    let dirtyTabIds: Set<UUID>
    let selectedFileId: UUID?
    var onSelectFile: (UUID) -> Void
    var onCloseFile: (UUID) -> Void
    let trailing: Trailing

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    init(
        files: [EditorTab],
        dirtyTabIds: Set<UUID> = [],
        selectedFileId: UUID?,
        onSelectFile: @escaping (UUID) -> Void,
        onCloseFile: @escaping (UUID) -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.files = files
        self.dirtyTabIds = dirtyTabIds
        self.selectedFileId = selectedFileId
        self.onSelectFile = onSelectFile
        self.onCloseFile = onCloseFile
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            if files.isEmpty {
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(files) { file in
                            FileTab(
                                file: file,
                                isDirty: dirtyTabIds.contains(file.id),
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

            trailing
                .padding(.trailing, Spacing.sm)
        }
        .frame(height: LayoutMetrics.compactToolbarHeight)
        .background(colors.toolbarBackground)
    }
}

// MARK: - File Tab (Pill)

struct FileTab: View {
    @Environment(\.colorScheme) private var colorScheme

    let file: EditorTab
    let isDirty: Bool
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
                Image(systemName: fileIcon(for: file))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)

                // File name
                Text(file.filename)
                    .font(Typography.caption)
                    .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)
                    .lineLimit(1)

                if file.kind == .file && isDirty {
                    Circle()
                        .fill(colors.warning)
                        .frame(width: 6, height: 6)
                }

                if file.kind == .diff {
                    Text("Diff")
                        .font(Typography.micro)
                        .foregroundStyle(colors.info)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 2)
                        .background(colors.info.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(isCloseHovered ? colors.foreground : colors.mutedForeground)
                        .frame(width: 14, height: 14)
                        .background(isCloseHovered ? colors.hoverBackground : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }
                .buttonStyle(.plain)
                .iconTooltip(IconTooltipSpec("Close tab"))
                .onHover { hovering in
                    isCloseHovered = hovering
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected ? colors.selectionBackground : (isHovered ? colors.hoverBackground : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(isSelected ? colors.selectionBorder : Color.clear, lineWidth: BorderWidth.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func fileIcon(for tab: EditorTab) -> String {
        if tab.kind == .diff {
            return "doc.text.magnifyingglass"
        }
        switch tab.fileExtension {
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
    @Environment(AppState.self) private var appState

    let tab: EditorTab
    @Bindable var editorState: EditorState

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var documentState: EditorDocumentState {
        editorState.document(for: tab.id) ?? EditorDocumentState()
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { editorState.document(for: tab.id)?.content ?? "" },
            set: { editorState.updateDocumentContent(for: tab.id, content: $0) }
        )
    }

    private var lineCount: Int {
        max(1, documentState.content.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    var body: some View {
        Group {
            if documentState.isLoading && !documentState.hasLoaded {
                ProgressView("Loading file...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = documentState.errorMessage, documentState.content.isEmpty {
                ErrorStateView(
                    icon: "doc.text",
                    title: "Failed to load file",
                    message: error
                )
            } else {
                VStack(spacing: 0) {
                    if let readOnlyReason = documentState.readOnlyReason {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: IconSize.xs))
                            Text(readOnlyReason)
                                .font(Typography.caption)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .foregroundStyle(colors.warning)
                        .background(colors.warning.opacity(0.08))
                    }

                    if let error = documentState.errorMessage, !error.isEmpty {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: IconSize.xs))
                            Text(error)
                                .font(Typography.caption)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .foregroundStyle(colors.destructive)
                        .background(colors.destructive.opacity(0.08))
                    }

                    TextEditor(text: contentBinding)
                        .font(GeistFont.mono(size: FontSize.sm, weight: .regular))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm)
                        .disabled(documentState.isReadOnly || documentState.isSaving)

                    HStack(spacing: Spacing.sm) {
                        Text("\(lineCount) lines")
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                        Spacer(minLength: 0)
                        if documentState.isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(colors.surface2)
                }
            }
        }
        .background(colors.editorBackground)
        .task(id: tab.id) {
            await editorState.ensureFileLoaded(
                tabId: tab.id,
                daemonClient: appState.daemonClient
            )
        }
    }
}

// MARK: - Diff Editor View

struct DiffEditorView: View {
    @Environment(\.colorScheme) private var colorScheme

    let path: String
    let diffState: DiffLoadState?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Group {
            if let state = diffState {
                if state.isLoading {
                    ProgressView("Loading diff...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = state.errorMessage {
                    ErrorStateView(
                        icon: "arrow.left.arrow.right",
                        title: "Failed to load diff",
                        message: error
                    )
                } else if let diff = state.diff {
                    DiffViewer(diff: diff)
                        .padding(Spacing.md)
                } else {
                    ErrorStateView(
                        icon: "doc.text.magnifyingglass",
                        title: "No diff available",
                        message: "There are no changes to display for \(path)",
                        iconColor: colors.mutedForeground
                    )
                }
            } else {
                ErrorStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No diff loaded",
                    message: "Diff has not been loaded for \(path)",
                    iconColor: colors.mutedForeground
                )
            }
        }
        .background(colors.editorBackground)
    }
}

#if DEBUG

private func makePreviewWorkspaceTabState(
    editorState: EditorState,
    selection: WorkspaceTabSelection = .conversation,
    terminalCount: Int = 0
) -> WorkspaceTabState {
    let state = WorkspaceTabState()
    state.resetForSession(PreviewData.sessionId1, workspacePath: PreviewData.repositories.first?.path)
    for _ in 0..<terminalCount {
        _ = state.createTerminalTab(for: PreviewData.sessionId1, workspacePath: PreviewData.repositories.first?.path)
    }

    switch selection {
    case .conversation:
        state.selectConversation()
    case .agentRuns(let agentId):
        state.openAgentRuns(agentId: agentId, title: "Preview Agent")
    case .terminal:
        if let firstTerminal = state.terminalTabs.first {
            state.selectTerminal(firstTerminal.id)
        }
    case .editor(let tabId):
        editorState.selectTab(id: tabId)
        state.selectEditor(tabId)
    }

    return state
}

#Preview("With Messages") {
    let editorState = EditorState()
    ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(editorState: editorState)
    )
    .environment(AppState.preview())
    .frame(width: 900, height: 600)
}

#Preview("Conversation Selected") {
    let editorState = EditorState.preview()

    return ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(editorState: editorState)
    )
    .environment(AppState.preview())
    .preferredColorScheme(.dark)
    .frame(width: 900, height: 600)
}

#Preview("Diff Selected") {
    let editorState = EditorState.preview()
    let diffTabId = editorState.tabs.first(where: { $0.kind == .diff })?.id ?? UUID()

    return ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(
            editorState: editorState,
            selection: .editor(diffTabId)
        )
    )
    .environment(AppState.preview())
    .preferredColorScheme(.dark)
    .frame(width: 900, height: 600)
}

#Preview("Terminal Selected") {
    let editorState = EditorState.preview()

    return ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(
            editorState: editorState,
            selection: .terminal(UUID()),
            terminalCount: 2
        )
    )
    .environment(AppState.preview())
    .preferredColorScheme(.dark)
    .frame(width: 900, height: 600)
}

#Preview("Runs Selected") {
    let editorState = EditorState.preview()
    let appState = AppState()
    let currentSession = Session(
        id: PreviewData.sessionId1,
        repositoryId: PreviewData.repoId1,
        title: "Implement WebSocket relay",
        agentId: "agent-preview",
        agentName: "Ops Agent",
        issueId: "ENG-123",
        issueTitle: "Investigate relay connection drift",
        issueURL: "https://example.com/issues/ENG-123",
        status: .active,
        createdAt: Date().addingTimeInterval(-7200),
        lastAccessed: Date()
    )
    let historicalRun = Session(
        id: PreviewData.sessionId4,
        repositoryId: PreviewData.repoId2,
        title: "Add rebase support",
        agentId: "agent-preview",
        agentName: "Ops Agent",
        issueId: "ENG-101",
        issueTitle: "Stabilize rebase workflow",
        issueURL: "https://example.com/issues/ENG-101",
        status: .archived,
        isWorktree: true,
        worktreePath: "/tmp/preview-agent-worktree",
        createdAt: Date().addingTimeInterval(-172800),
        lastAccessed: Date().addingTimeInterval(-86400)
    )
    appState.configureForPreview(
        repositories: PreviewData.repositories,
        sessions: [
            PreviewData.repoId1: [currentSession],
            PreviewData.repoId2: [historicalRun]
        ],
        selectedRepositoryId: PreviewData.repoId1,
        selectedSessionId: currentSession.id
    )

    return ChatPanel(
        session: currentSession,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(
            editorState: editorState,
            selection: .agentRuns("agent-preview")
        )
    )
    .environment(appState)
    .preferredColorScheme(.dark)
    .frame(width: 900, height: 600)
}

#Preview("With Messages (Light)") {
    let editorState = EditorState()
    ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(editorState: editorState)
    )
    .environment(AppState.preview())
    .preferredColorScheme(.light)
    .frame(width: 900, height: 600)
}

#Preview("With Messages (Dark)") {
    let editorState = EditorState()
    ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(editorState: editorState)
    )
    .environment(AppState.preview())
    .preferredColorScheme(.dark)
    .frame(width: 900, height: 600)
}

#Preview("Claude Active") {
    let editorState = EditorState()
    ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.sonnet),
        selectedThinkMode: .constant(.think),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(editorState: editorState)
    )
    .environment(AppState.preview(claudeRunning: true))
    .frame(width: 900, height: 600)
}

#Preview("Runtime Status - Running") {
    let runtimeStatus = RuntimeStatusEnvelope.legacyFallback(
        status: .running,
        errorMessage: nil,
        sessionId: PreviewData.sessionId1.uuidString,
        updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
    )
    let editorState = EditorState()

    return ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.sonnet),
        selectedThinkMode: .constant(.think),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(editorState: editorState)
    )
    .environment(AppState.preview(runtimeStatus: runtimeStatus))
    .frame(width: 900, height: 600)
}

#Preview("Runtime Status - Idle (Hidden)") {
    let runtimeStatus = RuntimeStatusEnvelope.legacyFallback(
        status: .idle,
        errorMessage: nil,
        sessionId: PreviewData.sessionId1.uuidString,
        updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
    )
    let editorState = EditorState()

    return ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.sonnet),
        selectedThinkMode: .constant(.think),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(editorState: editorState)
    )
    .environment(AppState.preview(runtimeStatus: runtimeStatus))
    .frame(width: 900, height: 600)
}

#Preview("Empty") {
    let editorState = EditorState()
    ChatPanel(
        session: FakeData.sessions.first,
        repository: nil,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: editorState,
        workspaceTabState: makePreviewWorkspaceTabState(editorState: editorState)
    )
    .environment(AppState())
    .frame(width: 900, height: 600)
}

#endif
