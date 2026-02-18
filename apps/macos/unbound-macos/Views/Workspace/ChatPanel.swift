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

    // Footer panel state
    @State private var isFooterExpanded: Bool = false
    @State private var footerHeight: CGFloat = 0
    @State private var footerDragStartHeight: CGFloat = 0
    @State private var isAtBottom: Bool = true
    @State private var seenMessageIds: Set<UUID> = []
    @State private var animateMessageIds: Set<UUID> = []
    @State private var renderInterval: ChatPerformanceSignposts.IntervalToken?

    // Editor tab close/save dialog state
    @State private var pendingCloseTabId: UUID?
    @State private var showUnsavedCloseDialog: Bool = false
    @State private var conflictTabId: UUID?
    @State private var conflictRevision: DaemonFileRevision?
    @State private var showConflictDialog: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Whether an editor tab is currently selected (vs. the session/chat tab)
    private var isEditorTabActive: Bool {
        editorState.selectedTabId != nil && !editorState.tabs.isEmpty
    }

    /// Currently selected editor tab
    private var selectedEditorTab: EditorTab? {
        guard let id = editorState.selectedTabId else { return nil }
        return editorState.tabs.first { $0.id == id }
    }

    private var selectedFileTab: EditorTab? {
        guard let tab = selectedEditorTab, tab.kind == .file else { return nil }
        return tab
    }

    private var dirtyTabIds: Set<UUID> {
        Set(
            editorState.documentsByTabId
                .filter { $0.value.isDirty }
                .map(\.key)
        )
    }

    private var canSaveSelectedFile: Bool {
        guard let selectedFileTab else { return false }
        return editorState.canSave(tabId: selectedFileTab.id)
    }

    private enum FooterConstants {
        static let barHeight: CGFloat = TerminalFooterTabTokens.barHeight
        static let handleHeight: CGFloat = 12
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

    /// Messages from live state
    private var messages: [ChatMessage] {
        liveState?.messages ?? []
    }

    /// Tool history from live state
    private var toolHistory: [ToolHistoryEntry] {
        liveState?.toolHistory ?? []
    }

    /// Currently active sub-agent (if any)
    private var activeSubAgents: [ActiveSubAgent] {
        liveState?.activeSubAgents ?? []
    }

    /// Currently active standalone tools (not in a sub-agent)
    private var activeTools: [ActiveTool] {
        liveState?.activeTools ?? []
    }

    /// Whether there's any active tool state to display
    private var hasActiveToolState: Bool {
        !activeSubAgents.isEmpty || !activeTools.isEmpty || !toolHistory.isEmpty
    }

    /// Coalesced scroll identity - combines factors that should trigger auto-scroll
    /// Using a single hash prevents multiple scroll operations per update
    private var scrollIdentity: Int {
        var hasher = Hasher()
        hasher.combine(messages.count)
        hasher.combine(toolHistory.count)
        hasher.combine(activeSubAgents.count)
        hasher.combine(activeSubAgents.last?.id)
        hasher.combine(activeSubAgents.last?.childTools.count)
        hasher.combine(activeSubAgents.last?.childTools.last?.id)
        hasher.combine(activeTools.last?.id)
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

    private var canSendMessages: Bool {
        liveState?.canSendMessage ?? true
    }

    private var runtimeStatusSummary: (status: CodingSessionRuntimeStatus, errorMessage: String?)? {
        guard let liveState else { return nil }
        return (
            status: liveState.codingSessionStatus,
            errorMessage: liveState.codingSessionErrorMessage
        )
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
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if isEditorTabActive {
                    editorColumn
                } else {
                    chatColumn
                        .padding(.bottom, FooterConstants.barHeight)

                    footerPanel(availableHeight: geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: session?.id) {
            if let state = liveState {
                await state.activate()
            }
        }
        .onChange(of: session?.id) { _, _ in
            seenMessageIds.removeAll()
            animateMessageIds.removeAll()
            renderInterval = nil
            isAtBottom = true
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
        .confirmationDialog(
            "Unsaved changes",
            isPresented: $showUnsavedCloseDialog,
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task { await saveAndClosePendingTab() }
            }
            Button("Discard", role: .destructive) {
                if let tabId = pendingCloseTabId {
                    editorState.closeTab(id: tabId)
                }
                pendingCloseTabId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCloseTabId = nil
            }
        } message: {
            Text("Save changes before closing this tab?")
        }
        .confirmationDialog(
            "File changed on disk",
            isPresented: $showConflictDialog,
            titleVisibility: .visible
        ) {
            Button("Reload") {
                guard let tabId = conflictTabId else { return }
                Task {
                    await editorState.reloadFile(tabId: tabId, daemonClient: appState.daemonClient)
                    clearConflictState()
                }
            }
            Button("Overwrite") {
                guard let tabId = conflictTabId else { return }
                Task {
                    await overwriteAfterConflict(tabId: tabId)
                }
            }
            Button("Cancel", role: .cancel) {
                clearConflictState()
            }
        } message: {
            if let revision = conflictRevision {
                Text("Current revision token: \(revision.token)")
            } else {
                Text("The file was modified externally. Reload or overwrite your local edits.")
            }
        }
    }

    // MARK: - Tabbed Header

    private var tabbedHeader: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    // Session tab (non-closable)
                    CenterPanelTab(
                        icon: "bubble.left.and.bubble.right",
                        label: session?.displayTitle ?? "New conversation",
                        isSelected: !isEditorTabActive,
                        isClosable: false,
                        onSelect: { editorState.selectedTabId = nil },
                        onClose: {}
                    )

                    // Editor file/diff tabs (closable)
                    ForEach(editorState.tabs) { tab in
                        CenterPanelTab(
                            icon: fileIcon(for: tab),
                            label: tab.filename,
                            badge: tab.kind == .diff ? "Diff" : nil,
                            isDirty: dirtyTabIds.contains(tab.id),
                            isSelected: editorState.selectedTabId == tab.id,
                            isClosable: true,
                            onSelect: { editorState.selectTab(id: tab.id) },
                            onClose: { requestCloseTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.sm)
            }

            Spacer(minLength: 0)
        }
        .frame(height: LayoutMetrics.compactToolbarHeight)
        .background(colors.toolbarBackground)
    }

    // MARK: - Editor Column

    private var editorColumn: some View {
        VStack(spacing: 0) {
            tabbedHeader
            ShadcnDivider()
            editorContent
        }
        .frame(minWidth: 300)
        .background(colors.editorBackground)
        .background {
            Button("Save") {
                Task { await saveActiveFile() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .hidden()
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
            // Tabbed header
            tabbedHeader

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
                                repoPath: repository?.name
                                    ?? appState.repositories.first(where: { $0.id == session.repositoryId })?.name
                                    ?? "repository",
                                tip: FakeData.tipMessage
                            )
                        }
                        Spacer()
                    } else {
                        // Messages list with interleaved tool history
                        ScrollViewReader { proxy in
                            let toolHistoryByIndex = Dictionary(grouping: toolHistory, by: \.afterMessageIndex)
                            let animateIdsInOrder = messages.filter { animateMessageIds.contains($0.id) }.map(\.id)
                            let animateIndexById = Dictionary(uniqueKeysWithValues: animateIdsInOrder.enumerated().map { ($0.element, $0.offset) })

                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    sessionTimelineHeaderCard

                                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                        let shouldAnimate = animateMessageIds.contains(message.id) && isAtBottom
                                        let animationIndex = shouldAnimate ? (animateIndexById[message.id] ?? 0) : 0
                                        let isLastMessage = index == messages.count - 1

                                        ChatMessageRow(
                                            message: message,
                                            animationIndex: animationIndex,
                                            shouldAnimate: shouldAnimate,
                                            onQuestionSubmit: handleQuestionSubmit,
                                            onRowAppear: isLastMessage ? {
                                                if let activeInterval = renderInterval {
                                                    ChatPerformanceSignposts.endInterval(activeInterval, "lastRowAppear")
                                                    renderInterval = nil
                                                }
                                                ChatPerformanceSignposts.event("chat.lastRowAppear", "id=\(message.id.uuidString)")
                                            } : nil
                                        )
                                        .equatable()
                                        .id(message.id)

                                        // Render tool history entries that belong after this message
                                        ForEach(toolHistoryByIndex[index] ?? []) { entry in
                                            ToolHistoryEntryView(entry: entry)
                                        }
                                    }

                                    // Render active sub-agents with new AgentCardView
                                    if !activeSubAgents.isEmpty {
                                        VStack(alignment: .leading, spacing: Spacing.md) {
                                            ForEach(activeSubAgents) { subAgent in
                                                SubAgentView(activeSubAgent: subAgent)
                                            }
                                        }
                                        .padding(.horizontal, Spacing.lg)
                                        .padding(.vertical, Spacing.sm)
                                    }

                                    // Render active standalone tools (if any)
                                    if !activeTools.isEmpty {
                                        StandaloneToolCallsView(activeTools: activeTools)
                                            .padding(.horizontal, Spacing.lg)
                                            .padding(.vertical, Spacing.sm)
                                    }

                                    // Invisible scroll anchor at bottom for reliable scrolling
                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottomAnchor")
                                        .onAppear {
                                            isAtBottom = true
                                            if let activeInterval = renderInterval {
                                                ChatPerformanceSignposts.endInterval(activeInterval, "bottomAnchorVisible")
                                                renderInterval = nil
                                            }
                                        }
                                        .onDisappear {
                                            isAtBottom = false
                                        }
                                }
                            }
                            .onChange(of: scrollIdentity) { _, _ in
                                if let activeInterval = renderInterval {
                                    ChatPerformanceSignposts.endInterval(activeInterval, "superseded")
                                }
                                if isAtBottom {
                                    renderInterval = ChatPerformanceSignposts.beginInterval(
                                        "chat.render",
                                        "messages=\(messages.count) tools=\(toolHistory.count)"
                                    )
                                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                                } else {
                                    renderInterval = nil
                                }
                            }
                            .onChange(of: messages.map(\.id)) { _, newIds in
                                let currentIds = Set(newIds)

                                if seenMessageIds.isEmpty {
                                    seenMessageIds = currentIds
                                    return
                                }

                                let inserted = currentIds.subtracting(seenMessageIds)
                                guard !inserted.isEmpty else { return }

                                seenMessageIds.formUnion(inserted)

                                if isAtBottom {
                                    animateMessageIds.formUnion(inserted)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        animateMessageIds.subtract(inserted)
                                    }
                                }
                            }
                        }
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
                    .disabled(workspacePath == nil || !canSendMessages)
                } else {
                    // No session selected
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

    private var sessionTimelineHeaderCard: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(session?.displayTitle ?? "Session")
                    .font(Typography.bodyMedium)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)

                Text(session?.id.uuidString.lowercased() ?? "")
                    .font(Typography.mono)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text("Rendered")
                    .font(Typography.micro)
                    .foregroundStyle(colors.mutedForeground)
                Text("\(messages.count)")
                    .font(Typography.captionMedium)
                    .foregroundStyle(colors.foreground)
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

    // MARK: - Footer Panel

    private func footerPanel(availableHeight: CGFloat) -> some View {
        let expandedHeight = clampedFooterHeight(
            footerHeight == 0 ? defaultFooterHeight(availableHeight) : footerHeight,
            availableHeight: availableHeight
        )
        let panelHeight = isFooterExpanded ? expandedHeight : FooterConstants.barHeight

        return VStack(spacing: 0) {
            footerTabBar(availableHeight: availableHeight)

            if isFooterExpanded {
                ShadcnDivider()
                footerHandle(availableHeight: availableHeight)
                ShadcnDivider()

                footerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: .infinity, height: panelHeight, alignment: .top)
        .clipped()
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
            Button {
                toggleFooterExpansion(availableHeight: availableHeight)
            } label: {
                Text("Terminal")
                    .font(
                        GeistFont.sans(
                                size: TerminalFooterTabTokens.tabFontSize,
                                weight: TerminalFooterTabTokens.tabFontWeight
                            )
                        )
                    )
                    .tracking(TerminalFooterTabTokens.tabLetterSpacing)
                    .foregroundStyle(isFooterExpanded ? colors.foreground : colors.sidebarMeta)
                    .padding(.horizontal, TerminalFooterTabTokens.tabPaddingX)
                    .frame(height: FooterConstants.barHeight)
                    .background(isFooterExpanded ? colors.secondary : Color.clear)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: TerminalFooterTabTokens.tabCornerRadius,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(colors.border)
                    .frame(width: TerminalFooterTabTokens.tabBorderWidth)
            }

            Spacer()
        }
        .padding(.horizontal, TerminalFooterTabTokens.barPaddingX)
        .frame(height: FooterConstants.barHeight)
        .background(colors.muted)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colors.borderSecondary)
                .frame(height: BorderWidth.`default`)
        }
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
        terminalFooterContent
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

    private func toggleFooterExpansion(availableHeight: CGFloat) {
        if isFooterExpanded {
            collapseFooter()
        } else {
            expandFooter(availableHeight: availableHeight)
        }
    }

    private func expandFooter(availableHeight: CGFloat) {
        let targetHeight = footerHeight == 0 ? defaultFooterHeight(availableHeight) : footerHeight
        withAnimation(.easeOut(duration: 0.15)) {
            isFooterExpanded = true
            footerHeight = clampedFooterHeight(targetHeight, availableHeight: availableHeight)
        }
    }

    private func collapseFooter() {
        withAnimation(.easeOut(duration: 0.15)) {
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

    // MARK: - Tab Actions

    private func requestCloseTab(_ tabId: UUID) {
        if editorState.isDirty(tabId: tabId) {
            pendingCloseTabId = tabId
            showUnsavedCloseDialog = true
            return
        }
        editorState.closeTab(id: tabId)
    }

    private func saveActiveFile() async {
        guard let tab = selectedFileTab else { return }
        await performSave(
            tabId: tab.id,
            forceOverwrite: false,
            closeOnSuccess: false
        )
    }

    private func saveAndClosePendingTab() async {
        guard let tabId = pendingCloseTabId else { return }
        await performSave(
            tabId: tabId,
            forceOverwrite: false,
            closeOnSuccess: true
        )
    }

    private func overwriteAfterConflict(tabId: UUID) async {
        let shouldCloseAfterSave = pendingCloseTabId == tabId
        await performSave(
            tabId: tabId,
            forceOverwrite: true,
            closeOnSuccess: shouldCloseAfterSave
        )
        clearConflictState()
    }

    private func performSave(
        tabId: UUID,
        forceOverwrite: Bool,
        closeOnSuccess: Bool
    ) async {
        do {
            let outcome = try await editorState.saveFile(
                tabId: tabId,
                daemonClient: appState.daemonClient,
                forceOverwrite: forceOverwrite
            )
            switch outcome {
            case .saved:
                if closeOnSuccess {
                    editorState.closeTab(id: tabId)
                }
                pendingCloseTabId = nil
            case .noChanges:
                if closeOnSuccess {
                    editorState.closeTab(id: tabId)
                }
                pendingCloseTabId = nil
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
        pendingCloseTabId = nil
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

// MARK: - Center Panel Tab

struct CenterPanelTab: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let label: String
    var badge: String? = nil
    var isDirty: Bool = false
    let isSelected: Bool
    let isClosable: Bool
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
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)

                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)
                    .lineLimit(1)

                if isDirty {
                    Circle()
                        .fill(colors.warning)
                        .frame(width: 6, height: 6)
                }

                if let badge {
                    Text(badge)
                        .font(Typography.micro)
                        .foregroundStyle(colors.info)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 2)
                        .background(colors.info.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                }

                if isClosable {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(isCloseHovered ? colors.foreground : colors.mutedForeground)
                            .frame(width: 14, height: 14)
                            .background(isCloseHovered ? colors.hoverBackground : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
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
}

// MARK: - Chat Message Row (Equatable Wrapper)

private struct ChatMessageRow: View, Equatable {
    let message: ChatMessage
    let animationIndex: Int
    let shouldAnimate: Bool
    let onQuestionSubmit: ((AskUserQuestion) -> Void)?
    let onRowAppear: (() -> Void)?

    static func == (lhs: ChatMessageRow, rhs: ChatMessageRow) -> Bool {
        lhs.message == rhs.message &&
        lhs.animationIndex == rhs.animationIndex &&
        lhs.shouldAnimate == rhs.shouldAnimate
    }

    var body: some View {
        ChatMessageView(
            message: message,
            animationIndex: animationIndex,
            onQuestionSubmit: onQuestionSubmit,
            shouldAnimate: shouldAnimate,
            onRowAppear: onRowAppear
        )
    }
}

#Preview("With Messages") {
    ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: EditorState()
    )
    .environment(AppState.preview())
    .frame(width: 900, height: 600)
}

#Preview("With Messages (Light)") {
    ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: EditorState()
    )
    .environment(AppState.preview())
    .preferredColorScheme(.light)
    .frame(width: 900, height: 600)
}

#Preview("With Messages (Dark)") {
    ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: EditorState()
    )
    .environment(AppState.preview())
    .preferredColorScheme(.dark)
    .frame(width: 900, height: 600)
}

#Preview("Claude Active") {
    ChatPanel(
        session: PreviewData.allSessions.first,
        repository: PreviewData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.sonnet),
        selectedThinkMode: .constant(.think),
        isPlanMode: .constant(false),
        editorState: EditorState()
    )
    .environment(AppState.preview(claudeRunning: true))
    .frame(width: 900, height: 600)
}

#Preview("Empty") {
    ChatPanel(
        session: FakeData.sessions.first,
        repository: nil,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: EditorState()
    )
    .environment(AppState())
    .frame(width: 900, height: 600)
}
