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

    // Mock streaming state
    @State private var isStreaming: Bool = false

    // Footer panel state
    @State private var selectedTerminalTab: TerminalTab = .terminal
    @State private var isFooterExpanded: Bool = false
    @State private var footerHeight: CGFloat = 0
    @State private var footerDragStartHeight: CGFloat = 0

    // File editor state - multiple open files with tabs
    @State private var openFiles: [OpenFile] = [
        OpenFile(
            path: "src/auth/login.swift",
            content: """
            import Foundation

            class AuthManager {
                static let shared = AuthManager()

                private var currentUser: User?
                private let tokenStore = TokenStore()

                func authenticate(email: String, password: String) async throws -> User {
                    let credentials = Credentials(email: email, password: password)
                    let response = try await apiClient.post("/auth/login", body: credentials)
                    let user = try response.decode(User.self)

                    // Store the token
                    try await tokenStore.save(response.token)

                    currentUser = user
                    return user
                }

                func logout() async {
                    currentUser = nil
                    await tokenStore.clear()
                }

                var isAuthenticated: Bool {
                    currentUser != nil
                }
            }
            """,
            language: "swift"
        ),
        OpenFile(
            path: "src/models/User.swift",
            content: """
            import Foundation

            struct User: Codable, Identifiable {
                let id: UUID
                let email: String
                let name: String
                let avatarURL: URL?
                let createdAt: Date

                var initials: String {
                    name.split(separator: " ")
                        .prefix(2)
                        .compactMap { $0.first }
                        .map(String.init)
                        .joined()
                }
            }
            """,
            language: "swift"
        ),
        OpenFile(
            path: "src/api/endpoints.swift",
            content: """
            import Foundation

            enum APIEndpoint {
                case login
                case logout
                case user(id: UUID)
                case users

                var path: String {
                    switch self {
                    case .login: return "/auth/login"
                    case .logout: return "/auth/logout"
                    case .user(let id): return "/users/\\(id)"
                    case .users: return "/users"
                    }
                }
            }
            """,
            language: "swift"
        )
    ]
    @State private var selectedFileId: UUID?

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
            // Header with project name
            ChatHeader(projectName: repository?.name ?? "No Repository")

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
                FileEditorView(file: file)
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

// MARK: - Open File Model

struct OpenFile: Identifiable {
    let id = UUID()
    let path: String
    let content: String
    let language: String

    var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
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
                Image(systemName: fileIcon(for: file.language))
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

    private func fileIcon(for language: String) -> String {
        switch language.lowercased() {
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

    let file: OpenFile

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var lines: [String] {
        file.content.components(separatedBy: "\n")
    }

    var body: some View {
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
        isPlanMode: .constant(false)
    )
    .environment(MockAppState())
    .frame(width: 900, height: 600)
}
