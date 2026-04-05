//
//  ChatScrollView.swift
//  unbound-macos
//
//  Extracted scroll view component with local scroll/animation state.
//  Recreated when session changes via .id(sessionId).
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui.chat")

struct ChatSnapshotScrollView<Header: View>: View {
    let snapshot: ChatTimelineSnapshot
    let onQuestionSubmit: (AskUserQuestion) -> Void
    let onInitialRenderComplete: (() -> Void)?
    let onLatestContentVisible: (() -> Void)?
    @ViewBuilder let header: () -> Header

    @State private var isAtBottom: Bool = true
    @State private var seenRowIDs: Set<UUID> = []
    @State private var animateRowIDs: Set<UUID> = []
    @State private var renderInterval: ChatPerformanceSignposts.IntervalToken?
    /// Set to true once the bottomAnchor has appeared for the first time,
    /// indicating that the initial render is complete. scrollTo is suppressed
    /// until this is true — defaultScrollAnchor(.bottom) handles initial positioning.
    @State private var hasCompletedInitialRender: Bool = false

    private var scrollIdentity: Int {
        snapshot.scrollIdentity
    }

    var body: some View {
        ScrollViewReader { proxy in
            let toolHistorySnapshotsByIndex = snapshot.toolHistorySnapshotsByIndex
            let animateIdsInOrder = snapshot.rows.filter { animateRowIDs.contains($0.id) }.map(\.id)
            let animateIndexById = Dictionary(uniqueKeysWithValues: animateIdsInOrder.enumerated().map { ($0.element, $0.offset) })

            ScrollView {
                LazyVStack(spacing: 0) {
                    header()

                    ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, rowSnapshot in
                        let shouldAnimate = animateRowIDs.contains(rowSnapshot.id) && isAtBottom
                        let animationIndex = shouldAnimate ? (animateIndexById[rowSnapshot.id] ?? 0) : 0
                        let isLastRow = index == snapshot.rows.count - 1

                        ChatMessageSnapshotRow(
                            rowSnapshot: rowSnapshot,
                            animationIndex: animationIndex,
                            shouldAnimate: shouldAnimate,
                            onQuestionSubmit: onQuestionSubmit,
                            onRowAppear: isLastRow ? {
                                if let activeInterval = renderInterval {
                                    ChatPerformanceSignposts.endInterval(activeInterval, "lastSnapshotRowAppear")
                                    renderInterval = nil
                                }
                                ChatPerformanceSignposts.event("chat.lastRowAppear", "id=\(rowSnapshot.id.uuidString)")
                                if snapshot.publishedAt > 0 {
                                    let renderDuration = CFAbsoluteTimeGetCurrent() - snapshot.publishedAt
                                    logger.info("chatRender lastRow: duration=\(String(format: "%.3f", renderDuration))s rows=\(snapshot.rows.count)")
                                }
                                onLatestContentVisible?()
                            } : nil
                        )
                        .equatable()

                        ForEach(toolHistorySnapshotsByIndex[index] ?? []) { entrySnapshot in
                            ToolHistoryEntrySnapshotView(snapshot: entrySnapshot)
                        }
                    }

                    if let streamingRow = snapshot.streamingRow {
                        ChatMessageSnapshotRow(
                            rowSnapshot: streamingRow,
                            animationIndex: 0,
                            shouldAnimate: false,
                            onQuestionSubmit: onQuestionSubmit,
                            onRowAppear: nil
                        )
                        .equatable()
                    }

                    if !snapshot.activeSubAgents.isEmpty {
                        ParallelAgentsView(activeSubAgents: snapshot.activeSubAgents)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                    }

                    if !snapshot.activeToolRenderSnapshots.isEmpty {
                        StandaloneToolCallsView(renderSnapshots: snapshot.activeToolRenderSnapshots)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottomAnchor")
                        .onAppear {
                            DispatchQueue.main.async {
                                isAtBottom = true
                                hasCompletedInitialRender = true
                                if let activeInterval = renderInterval {
                                    ChatPerformanceSignposts.endInterval(activeInterval, "bottomAnchorVisible")
                                    renderInterval = nil
                                }
                                if snapshot.publishedAt > 0 {
                                    let renderDuration = CFAbsoluteTimeGetCurrent() - snapshot.publishedAt
                                    logger.info("chatRender: duration=\(String(format: "%.3f", renderDuration))s rows=\(snapshot.rows.count)")
                                }
                                onInitialRenderComplete?()
                                onLatestContentVisible?()
                            }
                        }
                        .onDisappear {
                            DispatchQueue.main.async {
                                isAtBottom = false
                            }
                        }
                }
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: scrollIdentity) { _, _ in
                DispatchQueue.main.async {
                    // Until the initial render completes (bottomAnchor appears),
                    // defaultScrollAnchor(.bottom) handles positioning natively.
                    // scrollTo during initial load forces full LazyVStack layout.
                    guard hasCompletedInitialRender else { return }

                    if let activeInterval = renderInterval {
                        ChatPerformanceSignposts.endInterval(activeInterval, "superseded")
                    }

                    if isAtBottom {
                        renderInterval = ChatPerformanceSignposts.beginInterval(
                            "chat.render",
                            "snapshotRows=\(snapshot.rows.count) history=\(snapshot.toolHistory.count)"
                        )
                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                    } else {
                        renderInterval = nil
                    }
                }
            }
            .onChange(of: snapshot.rowIDs) { _, newIDs in
                DispatchQueue.main.async {
                    let currentIDs = Set(newIDs)
                    if seenRowIDs.isEmpty {
                        seenRowIDs = currentIDs
                        return
                    }

                    let inserted = currentIDs.subtracting(seenRowIDs)
                    guard !inserted.isEmpty else { return }
                    seenRowIDs.formUnion(inserted)

                    if isAtBottom {
                        animateRowIDs.formUnion(inserted)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            animateRowIDs.subtract(inserted)
                        }
                    }
                }
            }
        }
    }
}

struct ChatMessageSnapshotRow: View, Equatable {
    let rowSnapshot: ChatMessageRowSnapshot
    let animationIndex: Int
    let shouldAnimate: Bool
    let onQuestionSubmit: ((AskUserQuestion) -> Void)?
    let onRowAppear: (() -> Void)?

    static func == (lhs: ChatMessageSnapshotRow, rhs: ChatMessageSnapshotRow) -> Bool {
        lhs.rowSnapshot.renderKey == rhs.rowSnapshot.renderKey &&
        lhs.animationIndex == rhs.animationIndex &&
        lhs.shouldAnimate == rhs.shouldAnimate
    }

    var body: some View {
        ChatMessageView(
            rowSnapshot: rowSnapshot,
            animationIndex: animationIndex,
            onQuestionSubmit: onQuestionSubmit,
            shouldAnimate: shouldAnimate,
            onRowAppear: onRowAppear
        )
    }
}
