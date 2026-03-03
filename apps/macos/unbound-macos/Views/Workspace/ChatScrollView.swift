//
//  ChatScrollView.swift
//  unbound-macos
//
//  Extracted scroll view component with local scroll/animation state.
//  Recreated when session changes via .id(sessionId).
//

import SwiftUI

struct ChatScrollView<Header: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let messages: [ChatMessage]
    let toolHistory: [ToolHistoryEntry]
    let activeSubAgents: [ActiveSubAgent]
    let activeTools: [ActiveTool]
    let streamingAssistantMessage: ChatMessage?
    let onQuestionSubmit: (AskUserQuestion) -> Void
    @ViewBuilder let header: () -> Header

    // Local state - automatically reset when view is recreated via .id()
    @State private var isAtBottom: Bool = true
    @State private var seenMessageIds: Set<UUID> = []
    @State private var animateMessageIds: Set<UUID> = []
    @State private var renderInterval: ChatPerformanceSignposts.IntervalToken?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Coalesced scroll identity - combines factors that should trigger auto-scroll
    private var scrollIdentity: Int {
        var hasher = Hasher()
        hasher.combine(messages.count)
        hasher.combine(toolHistory.count)
        hasher.combine(activeSubAgents.count)
        hasher.combine(activeSubAgents.last?.id)
        hasher.combine(activeSubAgents.last?.childTools.count)
        hasher.combine(activeSubAgents.last?.childTools.last?.id)
        hasher.combine(activeTools.last?.id)
        hasher.combine(streamingAssistantMessage?.textContent.count ?? 0)
        if let last = messages.last {
            hasher.combine(last.content.count)
            if case .text(let textContent) = last.content.last {
                hasher.combine(textContent.text.count)
            }
        }
        return hasher.finalize()
    }

    var body: some View {
        ScrollViewReader { proxy in
            let toolHistoryByIndex = Dictionary(grouping: toolHistory, by: \.afterMessageIndex)
            let animateIdsInOrder = messages.filter { animateMessageIds.contains($0.id) }.map(\.id)
            let animateIndexById = Dictionary(uniqueKeysWithValues: animateIdsInOrder.enumerated().map { ($0.element, $0.offset) })

            ScrollView {
                LazyVStack(spacing: 0) {
                    header()

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let shouldAnimate = animateMessageIds.contains(message.id) && isAtBottom
                        let animationIndex = shouldAnimate ? (animateIndexById[message.id] ?? 0) : 0
                        let isLastMessage = index == messages.count - 1

                        ChatMessageRow(
                            message: message,
                            animationIndex: animationIndex,
                            shouldAnimate: shouldAnimate,
                            onQuestionSubmit: onQuestionSubmit,
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

                        ForEach(toolHistoryByIndex[index] ?? []) { entry in
                            ToolHistoryEntryView(entry: entry)
                        }
                    }

                    if let streamingAssistantMessage {
                        ChatMessageRow(
                            message: streamingAssistantMessage,
                            animationIndex: 0,
                            shouldAnimate: false,
                            onQuestionSubmit: onQuestionSubmit,
                            onRowAppear: nil
                        )
                        .equatable()
                        .id(streamingAssistantMessage.id)
                    }

                    if !activeSubAgents.isEmpty {
                        ParallelAgentsView(activeSubAgents: activeSubAgents)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                    }

                    if !activeTools.isEmpty {
                        StandaloneToolCallsView(activeTools: activeTools)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                    }

                    // Invisible scroll anchor at bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottomAnchor")
                        .onAppear {
                            DispatchQueue.main.async {
                                isAtBottom = true
                                if let activeInterval = renderInterval {
                                    ChatPerformanceSignposts.endInterval(activeInterval, "bottomAnchorVisible")
                                    renderInterval = nil
                                }
                            }
                        }
                        .onDisappear {
                            DispatchQueue.main.async {
                                isAtBottom = false
                            }
                        }
                }
            }
            .onChange(of: scrollIdentity) { _, _ in
                DispatchQueue.main.async {
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
            }
            .onChange(of: messages.map(\.id)) { _, newIds in
                DispatchQueue.main.async {
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
    }
}

// MARK: - Chat Message Row (Equatable Wrapper)

struct ChatMessageRow: View, Equatable {
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
