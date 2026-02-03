//
//  ChatPanel.swift
//  mockup-macos
//
//  Shadcn-styled chat panel with mock data.
//  Split into two columns: chat on left, file editor on right.
//

import SwiftUI

struct ChatPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MockAppState.self) private var appState

    let session: Session?
    let repository: Repository?
    @Binding var chatInput: String
    @Binding var selectedModel: AIModel
    @Binding var selectedThinkMode: ThinkMode
    @Binding var isPlanMode: Bool
    @Bindable var editorState: EditorState

    // Mock streaming state
    @State private var isStreaming: Bool = false

    // Footer panel state
    @State private var selectedTerminalTab: TerminalTab = .terminal
    @State private var isFooterExpanded: Bool = false
    @State private var footerHeight: CGFloat = 0
    @State private var footerDragStartHeight: CGFloat = 0

    // Editor state is owned by WorkspaceView

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private enum FooterConstants {
        static let barHeight: CGFloat = 40  // Match ChatHeader and FileEditorTabBar
        static let handleHeight: CGFloat = 12
        static let minExpandedHeight: CGFloat = 160
        static let defaultExpandedRatio: CGFloat = 0.4
        static let maxExpandedRatio: CGFloat = 0.8
    }

    /// Mock messages - using messages with sub-agents to demonstrate sub-agent UI
    private var messages: [ChatMessage] {
        FakeData.messagesWithSubAgents
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
    }

    // MARK: - Chat Column

    private var chatColumn: some View {
        VStack(spacing: 0) {
            // Header with session title
            ChatHeader(sessionTitle: session?.displayTitle ?? "New conversation")

            ShadcnDivider()

            // Chat content
            VStack(spacing: 0) {
                if let session = session {
                    if messages.isEmpty {
                        // Welcome view for empty chat
                        WelcomeChatView(
                            repoPath: repository?.name ?? "repository",
                            tip: FakeData.tipMessage
                        )
                        Spacer()
                    } else {
                        // Messages list
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                        ChatMessageView(
                                            message: message,
                                            index: index
                                        )
                                        .id(message.id)
                                    }

                                    // Invisible scroll anchor at bottom
                                    Color.clear.frame(height: 1).id("bottomAnchor")
                                }
                            }
                        }
                    }

                    // Input field at bottom
                    ChatInputField(
                        text: $chatInput,
                        selectedModel: $selectedModel,
                        selectedThinkMode: $selectedThinkMode,
                        isPlanMode: $isPlanMode,
                        isStreaming: isStreaming,
                        onSend: sendMessage,
                        onCancel: cancelStream
                    )
                    .padding(Spacing.compact)
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

    /// Currently selected editor tab
    private var selectedTab: EditorTab? {
        if let id = editorState.selectedTabId {
            return editorState.tabs.first { $0.id == id }
        }
        return editorState.tabs.first
    }

    // MARK: - File Editor Column

    private var fileEditorColumn: some View {
        VStack(spacing: 0) {
            // Editor header with file tabs
            FileEditorTabBar(
                files: editorState.tabs,
                selectedFileId: editorState.selectedTabId ?? editorState.tabs.first?.id,
                onSelectFile: { id in
                    editorState.selectTab(id: id)
                },
                onCloseFile: { id in
                    editorState.closeTab(id: id)
                }
            )

            ShadcnDivider()

            // Editor content
            if let tab = selectedTab {
                switch tab.kind {
                case .file:
                    FileEditorView(content: tab.content ?? "", language: tab.language)
                case .diff:
                    DiffEditorView(path: tab.path, diffState: editorState.diffStates[tab.path])
                }
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
        let panelHeight = isFooterExpanded ? expandedHeight : 40

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
            ForEach(TerminalTab.allCases) { tab in
                Button {
                    handleFooterTabTap(tab, availableHeight: availableHeight)
                } label: {
                    Text(tab.rawValue)
                        .font(Typography.caption)
                        .foregroundStyle(selectedTerminalTab == tab ? colors.foreground : colors.mutedForeground)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: 40)
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
        Group {
            switch selectedTerminalTab {
            case .terminal:
                terminalMockContent
            case .output:
                footerPlaceholder("No output yet")
            case .problems:
                footerPlaceholder("No problems detected")
            case .scripts:
                footerPlaceholder("No scripts configured")
            }
        }
        .padding(Spacing.md)
    }

    private var terminalMockContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("$ ")
                .font(Typography.terminal)
                .foregroundStyle(colors.success)
            +
            Text("Ready")
                .font(Typography.terminal)
                .foregroundStyle(colors.foreground)
        }
    }

    private func footerPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(Typography.bodySmall)
            .foregroundStyle(colors.mutedForeground)
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

    // MARK: - Actions

    private func sendMessage() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // For mockup, just clear input
        chatInput = ""

        // Simulate streaming
        isStreaming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isStreaming = false
        }
    }

    private func cancelStream() {
        isStreaming = false
    }
}

// MARK: - File Editor Tab Bar

struct FileEditorTabBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let files: [EditorTab]
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

    let file: EditorTab
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

    private func fileIcon(for tab: EditorTab) -> String {
        if tab.kind == .diff {
            return "doc.text.magnifyingglass"
        }
        switch tab.fileExtension {
        case "swift": return "swift"
        case "javascript", "js": return "curlybraces"
        case "typescript", "ts": return "curlybraces"
        case "python", "py": return "chevron.left.forwardslash.chevron.right"
        case "rust", "rs": return "gearshape.2"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "markdown", "md": return "doc.richtext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "list.bullet.indent"
        default: return "doc.text"
        }
    }
}

// MARK: - File Editor View

struct FileEditorView: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: String
    let language: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var lines: [String] {
        content.components(separatedBy: "\n")
    }

    var body: some View {
        let highlighter = SyntaxHighlighter(language: language, colorScheme: colorScheme)
        GeometryReader { proxy in
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
                            let content = line.isEmpty ? " " : line
                            Text(highlighter.highlight(content))
                                .font(.system(size: FontSize.sm, design: .monospaced))
                                .frame(height: 20, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
        .background(colors.background)
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
            if let state = diffState, let diff = state.diff {
                DiffViewer(diff: diff)
                    .padding(Spacing.md)
            } else {
                Text("No diff available for \(path)")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(colors.background)
    }
}

#Preview {
    ChatPanel(
        session: FakeData.sessions.first,
        repository: FakeData.repositories.first,
        chatInput: .constant(""),
        selectedModel: .constant(.opus),
        selectedThinkMode: .constant(.none),
        isPlanMode: .constant(false),
        editorState: EditorState()
    )
    .environment(MockAppState())
    .frame(width: 900, height: 600)
}
