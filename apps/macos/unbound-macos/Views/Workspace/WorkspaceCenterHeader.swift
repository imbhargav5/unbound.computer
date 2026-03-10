//
//  WorkspaceCenterHeader.swift
//  unbound-macos
//
//  Center-pane tab strip for conversation, terminal, and editor tabs.
//

import SwiftUI

struct WorkspaceCenterHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: Session?
    @Bindable var editorState: EditorState
    @Bindable var workspaceTabState: WorkspaceTabState
    let onRequestCloseEditorTab: (UUID) -> Void
    let onRequestCloseTerminalTab: (UUID) -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                WorkspaceNavbarTab(
                    label: session?.displayTitle ?? "New conversation",
                    isSelected: workspaceTabState.selection == .conversation,
                    isClosable: false,
                    showsTrailingDivider: !workspaceTabState.terminalTabs.isEmpty || !editorState.tabs.isEmpty,
                    onSelect: { workspaceTabState.selectConversation() },
                    onClose: {}
                )

                ForEach(Array(workspaceTabState.terminalTabs.enumerated()), id: \.element.id) { index, tab in
                    WorkspaceNavbarTab(
                        label: tab.title,
                        isSelected: workspaceTabState.selection == .terminal(tab.id),
                        isClosable: true,
                        showsTrailingDivider: index < workspaceTabState.terminalTabs.count - 1 || !editorState.tabs.isEmpty,
                        onSelect: {
                            workspaceTabState.selectTerminal(tab.id)
                        },
                        onClose: {
                            onRequestCloseTerminalTab(tab.id)
                        }
                    )
                }

                ForEach(Array(editorState.tabs.enumerated()), id: \.element.id) { index, tab in
                    WorkspaceNavbarTab(
                        label: tab.filename,
                        badge: tab.kind == .diff ? "Diff" : nil,
                        isSelected: workspaceTabState.selection == .editor(tab.id),
                        isClosable: true,
                        showsTrailingDivider: index < editorState.tabs.count - 1,
                        onSelect: {
                            editorState.selectTab(id: tab.id)
                            workspaceTabState.selectEditor(tab.id)
                        },
                        onClose: {
                            onRequestCloseEditorTab(tab.id)
                        }
                    )
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(height: LayoutMetrics.compactToolbarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.card)
        .overlay(alignment: .bottom) {
            ShadcnDivider()
        }
    }
}

#if DEBUG

private func makeCenterHeaderPreviewState(
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
    case .terminal:
        if let terminalId = state.terminalTabs.first?.id {
            state.selectTerminal(terminalId)
        }
    case .editor(let tabId):
        editorState.selectTab(id: tabId)
        state.selectEditor(tabId)
    }

    return state
}

#Preview("Conversation") {
    let editorState = EditorState.preview()

    return WorkspaceCenterHeader(
        session: PreviewData.allSessions.first,
        editorState: editorState,
        workspaceTabState: makeCenterHeaderPreviewState(editorState: editorState),
        onRequestCloseEditorTab: { _ in },
        onRequestCloseTerminalTab: { _ in }
    )
    .preferredColorScheme(.dark)
    .frame(width: 900)
}

#Preview("Terminal") {
    let editorState = EditorState.preview()

    return WorkspaceCenterHeader(
        session: PreviewData.allSessions.first,
        editorState: editorState,
        workspaceTabState: makeCenterHeaderPreviewState(
            editorState: editorState,
            selection: .terminal(UUID()),
            terminalCount: 2
        ),
        onRequestCloseEditorTab: { _ in },
        onRequestCloseTerminalTab: { _ in }
    )
    .preferredColorScheme(.dark)
    .frame(width: 900)
}

#Preview("Diff") {
    let editorState = EditorState.preview()
    let diffTabId = editorState.tabs.first(where: { $0.kind == .diff })?.id ?? UUID()

    return WorkspaceCenterHeader(
        session: PreviewData.allSessions.first,
        editorState: editorState,
        workspaceTabState: makeCenterHeaderPreviewState(
            editorState: editorState,
            selection: .editor(diffTabId)
        ),
        onRequestCloseEditorTab: { _ in },
        onRequestCloseTerminalTab: { _ in }
    )
    .preferredColorScheme(.dark)
    .frame(width: 900)
}

#endif
