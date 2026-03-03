//
//  TerminalFooterPanel.swift
//  unbound-macos
//
//  Extracted terminal footer component with local terminal state.
//  Recreated when session changes via .id(sessionId).
//

import SwiftUI

struct TerminalFooterPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let workspacePath: String?
    let availableHeight: CGFloat

    // Local state - automatically reset when view is recreated via .id()
    @State private var isFooterExpanded: Bool = false
    @State private var footerHeight: CGFloat = 0
    @State private var footerDragStartHeight: CGFloat = 0
    @State private var terminalTabs: [FooterTerminalTab] = []
    @State private var activeFooterTerminalTabId: UUID?
    @State private var terminalTabSequence: Int = 0

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private enum FooterConstants {
        static let barHeight: CGFloat = TerminalFooterTabTokens.barHeight
        static let handleHeight: CGFloat = 12
        static let minExpandedHeight: CGFloat = 160
        static let defaultExpandedRatio: CGFloat = 0.4
        static let maxExpandedRatio: CGFloat = 0.8
    }

    private var activeFooterTerminalTab: FooterTerminalTab? {
        guard let activeFooterTerminalTabId else { return nil }
        return terminalTabs.first { $0.id == activeFooterTerminalTabId }
    }

    var panelHeight: CGFloat {
        let expandedHeight = clampedFooterHeight(
            footerHeight == 0 ? defaultFooterHeight(availableHeight) : footerHeight,
            availableHeight: availableHeight
        )
        return isFooterExpanded ? expandedHeight : FooterConstants.barHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            footerTabBar

            if isFooterExpanded {
                ShadcnDivider()
                footerHandle
                ShadcnDivider()

                footerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: panelHeight, alignment: .top)
        .clipped()
        .background(colors.card)
        .overlay(alignment: .top) {
            ShadcnDivider()
        }
        .onChange(of: availableHeight) { _, newHeight in
            DispatchQueue.main.async {
                guard isFooterExpanded else { return }
                footerHeight = clampedFooterHeight(
                    footerHeight == 0 ? defaultFooterHeight(newHeight) : footerHeight,
                    availableHeight: newHeight
                )
            }
        }
        .onChange(of: workspacePath) { _, _ in
            DispatchQueue.main.async {
                ensureFooterTerminalTabState()
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                ensureFooterTerminalTabState()
            }
        }
    }

    // MARK: - Tab Bar

    private var footerTabBar: some View {
        HStack(spacing: 0) {
            if terminalTabs.isEmpty {
                Text("Terminal")
                    .font(
                        GeistFont.sans(
                            size: TerminalFooterTabTokens.tabFontSize,
                            weight: TerminalFooterTabTokens.tabFontWeight
                        )
                    )
                    .tracking(TerminalFooterTabTokens.tabLetterSpacing)
                    .foregroundStyle(colors.sidebarMeta)
                    .padding(.horizontal, TerminalFooterTabTokens.tabPaddingX)
                    .frame(height: FooterConstants.barHeight)
            } else {
                ForEach(terminalTabs) { tab in
                    HStack(spacing: TerminalFooterTabTokens.tabContentSpacing) {
                        Button {
                            selectFooterTerminalTab(tab.id)
                            if !isFooterExpanded {
                                expandFooter()
                            }
                        } label: {
                            Text(tab.title)
                                .lineLimit(1)
                                .font(
                                    GeistFont.sans(
                                        size: TerminalFooterTabTokens.tabFontSize,
                                        weight: TerminalFooterTabTokens.tabFontWeight
                                    )
                                )
                                .tracking(TerminalFooterTabTokens.tabLetterSpacing)
                                .foregroundStyle(
                                    activeFooterTerminalTabId == tab.id ? colors.foreground : colors.sidebarMeta
                                )
                                .padding(.horizontal, TerminalFooterTabTokens.tabPaddingX)
                                .frame(height: FooterConstants.barHeight)
                                .background(activeFooterTerminalTabId == tab.id ? colors.secondary : Color.clear)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: TerminalFooterTabTokens.tabCornerRadius,
                                        style: .continuous
                                    )
                                )
                        }
                        .buttonStyle(.plain)

                        if terminalTabs.count > 1 {
                            Button {
                                closeFooterTerminalTab(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: TerminalFooterTabTokens.closeIconSize, weight: .medium))
                                    .foregroundStyle(colors.sidebarMeta)
                                    .frame(
                                        width: TerminalFooterTabTokens.closeButtonSize,
                                        height: TerminalFooterTabTokens.closeButtonSize
                                    )
                                    .background(colors.muted)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: TerminalFooterTabTokens.closeButtonCornerRadius,
                                            style: .continuous
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, TerminalFooterTabTokens.controlPaddingX)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(colors.border)
                            .frame(width: TerminalFooterTabTokens.tabBorderWidth)
                    }
                }

                Button {
                    addFooterTerminalTab()
                    if !isFooterExpanded {
                        expandFooter()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: TerminalFooterTabTokens.addIconSize, weight: .semibold))
                        .foregroundStyle(colors.sidebarMeta)
                        .frame(
                            width: TerminalFooterTabTokens.addButtonSize,
                            height: TerminalFooterTabTokens.addButtonSize
                        )
                        .background(colors.secondary)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: TerminalFooterTabTokens.closeButtonCornerRadius,
                                style: .continuous
                            )
                        )
                        .padding(.horizontal, TerminalFooterTabTokens.controlPaddingX)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                toggleFooterExpansion()
            } label: {
                Image(systemName: isFooterExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.sidebarMeta)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, TerminalFooterTabTokens.controlPaddingX)
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

    // MARK: - Handle

    private var footerHandle: some View {
        Capsule()
            .fill(colors.mutedForeground.opacity(0.4))
            .frame(width: 32, height: 4)
            .frame(maxWidth: .infinity, maxHeight: FooterConstants.handleHeight)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
    }

    // MARK: - Content

    private var footerContent: some View {
        Group {
            if terminalTabs.isEmpty {
                Text("No workspace selected")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Spacing.md)
            } else {
                ZStack {
                    ForEach(terminalTabs) { tab in
                        TerminalContainer(tabId: tab.id, workingDirectory: tab.workingDirectory)
                            .opacity(activeFooterTerminalTabId == tab.id ? 1 : 0)
                            .allowsHitTesting(activeFooterTerminalTabId == tab.id)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleFooterExpansion() {
        if isFooterExpanded {
            collapseFooter()
        } else {
            expandFooter()
        }
    }

    private func expandFooter() {
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

    private var resizeGesture: some Gesture {
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

    private func ensureFooterTerminalTabState() {
        guard let path = workspacePath else {
            terminalTabs.removeAll()
            activeFooterTerminalTabId = nil
            return
        }

        if terminalTabs.isEmpty {
            let initialTab = makeFooterTerminalTab(workingDirectory: path)
            terminalTabs = [initialTab]
            activeFooterTerminalTabId = initialTab.id
            return
        }

        terminalTabs = terminalTabs.map { tab in
            var updatedTab = tab
            if updatedTab.workingDirectory.isEmpty {
                updatedTab.workingDirectory = path
            }
            return updatedTab
        }

        if activeFooterTerminalTab == nil, let firstTab = terminalTabs.first {
            activeFooterTerminalTabId = firstTab.id
        }
    }

    private func makeFooterTerminalTab(workingDirectory: String) -> FooterTerminalTab {
        terminalTabSequence += 1
        return FooterTerminalTab(
            id: UUID(),
            title: "Terminal \(terminalTabSequence)",
            workingDirectory: workingDirectory
        )
    }

    private func addFooterTerminalTab() {
        guard let path = workspacePath else { return }
        let newTab = makeFooterTerminalTab(workingDirectory: path)
        terminalTabs.append(newTab)
        activeFooterTerminalTabId = newTab.id
    }

    private func selectFooterTerminalTab(_ tabId: UUID) {
        guard terminalTabs.contains(where: { $0.id == tabId }) else { return }
        activeFooterTerminalTabId = tabId
    }

    private func closeFooterTerminalTab(_ tabId: UUID) {
        guard let closingIndex = terminalTabs.firstIndex(where: { $0.id == tabId }) else { return }
        let wasActive = activeFooterTerminalTabId == tabId

        terminalTabs.remove(at: closingIndex)

        if terminalTabs.isEmpty {
            guard let path = workspacePath else {
                activeFooterTerminalTabId = nil
                return
            }
            let replacementTab = makeFooterTerminalTab(workingDirectory: path)
            terminalTabs = [replacementTab]
            activeFooterTerminalTabId = replacementTab.id
            return
        }

        guard wasActive else { return }
        let fallbackIndex = min(closingIndex, terminalTabs.count - 1)
        activeFooterTerminalTabId = terminalTabs[fallbackIndex].id
    }
}

// MARK: - Terminal Tab Model

struct FooterTerminalTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var workingDirectory: String
}
