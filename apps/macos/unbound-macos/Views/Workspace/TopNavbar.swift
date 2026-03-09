//
//  TopNavbar.swift
//  unbound-macos
//
//  Top navigation bar replacing the empty titlebar gap.
//  Contains sidebar toggles, settings, and a draggable center area.
//

import SwiftUI

struct TopNavbar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    let session: Session?
    @Bindable var editorState: EditorState
    @Bindable var workspaceTabState: WorkspaceTabState
    let onRequestCloseEditorTab: (UUID) -> Void
    let onRequestCloseTerminalTab: (UUID) -> Void
    let onOpenSettings: () -> Void

    /// Space needed for traffic lights (close, minimize, zoom)
    private let trafficLightWidth: CGFloat = 78

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left section: traffic light spacing + left sidebar toggle
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: trafficLightWidth)

                if !appState.localSettings.isZenModeEnabled {
                    IconButton(systemName: "sidebar.left", action: {
                        withAnimation(.easeOut(duration: Duration.fast)) {
                            appState.localSettings.leftSidebarVisible.toggle()
                        }
                    })
                }
            }

            workspaceTabStrip
                .frame(maxWidth: .infinity, alignment: .leading)

            // Right section: right sidebar toggle + settings
            HStack(spacing: Spacing.xxs) {
                if !appState.localSettings.isZenModeEnabled {
                    IconButton(systemName: "sidebar.right", action: {
                        withAnimation(.easeOut(duration: Duration.fast)) {
                            appState.localSettings.rightSidebarVisible.toggle()
                        }
                    })

                    IconButton(systemName: "gearshape", action: onOpenSettings)
                }
            }
            .padding(.trailing, Spacing.sm)
        }
        .frame(height: LayoutMetrics.compactToolbarHeight)
        .frame(maxWidth: .infinity)
        .background(colors.toolbarBackground)
        .background(WindowDragView())
        .overlay(alignment: .bottom) {
            ShadcnDivider()
        }
    }

    private var workspaceTabStrip: some View {
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
    }
}
