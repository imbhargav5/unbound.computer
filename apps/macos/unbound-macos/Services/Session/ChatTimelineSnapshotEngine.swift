import ClaudeConversationTimeline
import Foundation

actor ChatTimelineSnapshotEngine {
    struct Input {
        let messages: [ChatMessage]
        let toolHistory: [ToolHistoryEntry]
        let activeSubAgents: [ActiveSubAgent]
        let activeTools: [ActiveTool]
        let streamingAssistantMessage: ChatMessage?
    }

    private struct TextArtifactKey: Hashable {
        let textID: UUID
        let textHash: Int
        let isAssistantMessage: Bool
    }

    private struct ToolArtifactKey: Hashable {
        let toolID: UUID
        let status: ToolStatus
        let inputHash: Int
        let outputHash: Int
    }

    private var rowByMessageID: [UUID: ChatMessageRowSnapshot] = [:]
    private var messageFingerprintByID: [UUID: Int] = [:]
    private var textArtifactByKey: [TextArtifactKey: TextRenderSnapshot] = [:]
    private var toolArtifactByKey: [ToolArtifactKey: ToolRenderSnapshot] = [:]

    func build(_ input: Input) async -> ChatTimelineSnapshot {
        let buildInterval = ChatPerformanceSignposts.beginInterval(
            "chat.snapshot.build",
            "messages=\(input.messages.count)"
        )

        let deduped = ChatToolSurfaceDeduper.dedupe(
            messages: input.messages,
            toolHistory: input.toolHistory,
            activeSubAgents: input.activeSubAgents,
            activeTools: input.activeTools
        )

        var nextRows: [ChatMessageRowSnapshot] = []
        nextRows.reserveCapacity(input.messages.count)

        var reusedRows = 0
        var retainedMessageIDs: Set<UUID> = []

        for message in input.messages {
            retainedMessageIDs.insert(message.id)
            let (row, reused) = buildRowSnapshot(for: message)
            if reused {
                reusedRows += 1
            }
            nextRows.append(row)
        }

        rowByMessageID = rowByMessageID.filter { retainedMessageIDs.contains($0.key) }
        messageFingerprintByID = messageFingerprintByID.filter { retainedMessageIDs.contains($0.key) }

        let streamingRow: ChatMessageRowSnapshot?
        if let streamingMessage = input.streamingAssistantMessage {
            streamingRow = buildStreamingRowSnapshot(from: streamingMessage)
        } else {
            streamingRow = nil
        }

        ChatPerformanceSignposts.event(
            "chat.snapshot.reuse",
            "reused=\(reusedRows) total=\(nextRows.count)"
        )

        var revisionHasher = Hasher()
        revisionHasher.combine(nextRows.count)
        for row in nextRows {
            revisionHasher.combine(row.id)
            revisionHasher.combine(row.renderKey)
        }

        revisionHasher.combine(streamingRow?.id)
        revisionHasher.combine(streamingRow?.renderKey)

        revisionHasher.combine(deduped.visibleToolHistory.count)
        revisionHasher.combine(deduped.visibleActiveSubAgents.count)
        revisionHasher.combine(deduped.visibleActiveTools.count)

        for entry in deduped.visibleToolHistory.suffix(24) {
            revisionHasher.combine(entry.id)
            revisionHasher.combine(entry.afterMessageIndex)
            revisionHasher.combine(entry.tools.count)
            for tool in entry.tools {
                revisionHasher.combine(Self.activeToolSignature(tool))
            }
            if let subAgent = entry.subAgent {
                revisionHasher.combine(subAgent.id)
                revisionHasher.combine(subAgent.status.rawValue)
                revisionHasher.combine(Self.stringSignature(subAgent.description))
                revisionHasher.combine(subAgent.childTools.count)
                for childTool in subAgent.childTools {
                    revisionHasher.combine(Self.activeToolSignature(childTool))
                }
            }
        }

        for subAgent in deduped.visibleActiveSubAgents {
            revisionHasher.combine(subAgent.id)
            revisionHasher.combine(subAgent.status.rawValue)
            revisionHasher.combine(Self.stringSignature(subAgent.description))
            revisionHasher.combine(subAgent.childTools.count)
            for childTool in subAgent.childTools {
                revisionHasher.combine(Self.activeToolSignature(childTool))
            }
        }

        for tool in deduped.visibleActiveTools {
            revisionHasher.combine(tool.id)
            revisionHasher.combine(tool.name)
            revisionHasher.combine(tool.status.rawValue)
            revisionHasher.combine(Self.stringSignature(tool.inputPreview))
            revisionHasher.combine(Self.stringSignature(tool.output))
        }

        let computedToolHistoryByIndex = Dictionary(
            grouping: deduped.visibleToolHistory,
            by: \.afterMessageIndex
        )
        let computedRowIDs = nextRows.map(\.id)
        let computedRenderedMessageCount = nextRows.count + (streamingRow == nil ? 0 : 1)
        let computedHasActiveToolState = !deduped.visibleActiveSubAgents.isEmpty
            || !deduped.visibleActiveTools.isEmpty
            || !deduped.visibleToolHistory.isEmpty
        let computedIsEmpty = nextRows.isEmpty
            && streamingRow == nil
            && !computedHasActiveToolState

        let finalRevision = revisionHasher.finalize()

        var scrollHasher = Hasher()
        scrollHasher.combine(finalRevision)
        scrollHasher.combine(nextRows.count)
        scrollHasher.combine(deduped.visibleToolHistory.count)
        scrollHasher.combine(deduped.visibleActiveSubAgents.count)
        scrollHasher.combine(deduped.visibleActiveTools.count)
        scrollHasher.combine(streamingRow?.renderKey)
        let computedScrollIdentity = scrollHasher.finalize()

        // Pre-compute tool history entry snapshots
        let computedToolHistorySnapshots = deduped.visibleToolHistory.map { entry in
            buildToolHistoryEntrySnapshot(for: entry)
        }
        let computedToolHistorySnapshotsByIndex = Dictionary(
            grouping: computedToolHistorySnapshots,
            by: \.afterMessageIndex
        )

        // Pre-compute active tool render snapshots
        let computedActiveToolRenderSnapshots = deduped.visibleActiveTools.map { tool in
            buildActiveToolRenderSnapshot(for: tool)
        }

        let snapshot = ChatTimelineSnapshot(
            revision: finalRevision,
            rows: nextRows,
            toolHistory: deduped.visibleToolHistory,
            activeSubAgents: deduped.visibleActiveSubAgents,
            activeTools: deduped.visibleActiveTools,
            streamingRow: streamingRow,
            toolHistoryByIndex: computedToolHistoryByIndex,
            rowIDs: computedRowIDs,
            scrollIdentity: computedScrollIdentity,
            renderedMessageCount: computedRenderedMessageCount,
            hasActiveToolState: computedHasActiveToolState,
            isEmpty: computedIsEmpty,
            toolHistorySnapshots: computedToolHistorySnapshots,
            toolHistorySnapshotsByIndex: computedToolHistorySnapshotsByIndex,
            activeToolRenderSnapshots: computedActiveToolRenderSnapshots,
            publishedAt: CFAbsoluteTimeGetCurrent()
        )

        ChatPerformanceSignposts.endInterval(
            buildInterval,
            "rows=\(snapshot.rows.count) history=\(snapshot.toolHistory.count)"
        )

        return snapshot
    }

    func updateStreamingRow(
        streamingMessage: ChatMessage?,
        existing: ChatTimelineSnapshot
    ) async -> ChatTimelineSnapshot {
        let interval = ChatPerformanceSignposts.beginInterval(
            "chat.snapshot.streamingUpdate",
            "existing=\(existing.rows.count)"
        )

        let streamingRow: ChatMessageRowSnapshot?
        if let streamingMessage {
            streamingRow = buildStreamingRowSnapshot(from: streamingMessage)
        } else {
            streamingRow = nil
        }

        let renderedMessageCount = existing.rows.count + (streamingRow == nil ? 0 : 1)

        var revisionHasher = Hasher()
        revisionHasher.combine(existing.revision)
        revisionHasher.combine(streamingRow?.id)
        revisionHasher.combine(streamingRow?.renderKey)
        let revision = revisionHasher.finalize()

        var scrollHasher = Hasher()
        scrollHasher.combine(revision)
        scrollHasher.combine(existing.rows.count)
        scrollHasher.combine(existing.toolHistory.count)
        scrollHasher.combine(existing.activeSubAgents.count)
        scrollHasher.combine(existing.activeTools.count)
        scrollHasher.combine(streamingRow?.renderKey)
        let scrollIdentity = scrollHasher.finalize()

        let snapshot = ChatTimelineSnapshot(
            revision: revision,
            rows: existing.rows,
            toolHistory: existing.toolHistory,
            activeSubAgents: existing.activeSubAgents,
            activeTools: existing.activeTools,
            streamingRow: streamingRow,
            toolHistoryByIndex: existing.toolHistoryByIndex,
            rowIDs: existing.rowIDs,
            scrollIdentity: scrollIdentity,
            renderedMessageCount: renderedMessageCount,
            hasActiveToolState: existing.hasActiveToolState,
            isEmpty: existing.isEmpty && streamingRow == nil,
            toolHistorySnapshots: existing.toolHistorySnapshots,
            toolHistorySnapshotsByIndex: existing.toolHistorySnapshotsByIndex,
            activeToolRenderSnapshots: existing.activeToolRenderSnapshots,
            publishedAt: CFAbsoluteTimeGetCurrent()
        )

        ChatPerformanceSignposts.endInterval(interval, "streamingOnly")
        return snapshot
    }

    private func buildStreamingRowSnapshot(from message: ChatMessage) -> ChatMessageRowSnapshot {
        let render = buildRenderableBlocks(from: message, isStreamingOverride: true)
        return ChatMessageRowSnapshot(
            id: message.id,
            role: message.role,
            timestamp: message.timestamp,
            sequenceNumber: message.sequenceNumber,
            isStreaming: true,
            renderKey: render.messageFingerprint,
            blocks: render.blocks,
            fileChangeSummary: render.fileChangeSummary
        )
    }

    private func buildRowSnapshot(for message: ChatMessage) -> (ChatMessageRowSnapshot, Bool) {
        let fingerprint = Self.messageFingerprint(for: message)
        if let previousFingerprint = messageFingerprintByID[message.id],
           previousFingerprint == fingerprint,
           let existing = rowByMessageID[message.id] {
            return (existing, true)
        }

        let rowBuildInterval = ChatPerformanceSignposts.beginInterval(
            "chat.snapshot.rowBuild",
            "id=\(message.id.uuidString)"
        )

        let render = buildRenderableBlocks(from: message, isStreamingOverride: message.isStreaming)

        let row = ChatMessageRowSnapshot(
            id: message.id,
            role: message.role,
            timestamp: message.timestamp,
            sequenceNumber: message.sequenceNumber,
            isStreaming: message.isStreaming,
            renderKey: render.messageFingerprint,
            blocks: render.blocks,
            fileChangeSummary: render.fileChangeSummary
        )

        rowByMessageID[message.id] = row
        messageFingerprintByID[message.id] = fingerprint

        ChatPerformanceSignposts.endInterval(rowBuildInterval, "blocks=\(row.blocks.count)")
        return (row, false)
    }

    private struct RenderResult {
        let blocks: [ChatRenderableBlockSnapshot]
        let fileChangeSummary: FileChangeSummarySnapshot
        let messageFingerprint: Int
    }

    private func buildRenderableBlocks(
        from message: ChatMessage,
        isStreamingOverride: Bool
    ) -> RenderResult {
        let isUser = message.role == .user
        let displayContent = deduplicatedDisplayContent(for: message)

        var blocks: [ChatRenderableBlockSnapshot] = []
        var pendingStandaloneTools: [ToolRenderSnapshot] = []
        var pendingSubAgents: [SubAgentRenderSnapshot] = []

        func flushPendingTools() {
            guard !pendingStandaloneTools.isEmpty else { return }
            blocks.append(.standaloneTools(pendingStandaloneTools))
            pendingStandaloneTools.removeAll(keepingCapacity: true)
        }

        func flushPendingSubAgents() {
            guard !pendingSubAgents.isEmpty else { return }
            blocks.append(.parallelAgents(pendingSubAgents))
            pendingSubAgents.removeAll(keepingCapacity: true)
        }

        for content in displayContent {
            if !isUser, case .fileChange = content {
                continue
            }

            if case .toolUse(let toolUse) = content {
                flushPendingSubAgents()
                pendingStandaloneTools.append(buildToolSnapshot(for: toolUse))
                continue
            }

            if case .subAgentActivity(let activity) = content {
                flushPendingTools()
                pendingSubAgents.append(buildSubAgentSnapshot(for: activity))
                continue
            }

            flushPendingTools()
            flushPendingSubAgents()
            blocks.append(.content(buildContentSnapshot(content, isAssistantMessage: !isUser)))
        }

        flushPendingTools()
        flushPendingSubAgents()

        let fileChanges = displayContent.compactMap { content -> FileChange? in
            if case .fileChange(let fileChange) = content {
                return fileChange
            }
            return nil
        }

        let fileSummary = FileChangeSummarySnapshot(
            files: fileChanges,
            totalLinesAdded: fileChanges.reduce(into: 0) { partial, fileChange in
                partial += fileChange.linesAdded
            },
            totalLinesRemoved: fileChanges.reduce(into: 0) { partial, fileChange in
                partial += fileChange.linesRemoved
            }
        )

        var messageHasher = Hasher()
        messageHasher.combine(message.id)
        messageHasher.combine(message.role)
        messageHasher.combine(message.sequenceNumber)
        messageHasher.combine(isStreamingOverride)
        messageHasher.combine(blocks.map(\.id))
        messageHasher.combine(fileSummary.files.count)
        messageHasher.combine(fileSummary.totalLinesAdded)
        messageHasher.combine(fileSummary.totalLinesRemoved)

        return RenderResult(
            blocks: blocks,
            fileChangeSummary: fileSummary,
            messageFingerprint: messageHasher.finalize()
        )
    }

    private func buildContentSnapshot(
        _ content: MessageContent,
        isAssistantMessage: Bool
    ) -> MessageContentSnapshot {
        switch content {
        case .text(let textContent):
            return .text(buildTextSnapshot(for: textContent, isAssistantMessage: isAssistantMessage))
        case .codeBlock(let codeBlock):
            return .codeBlock(codeBlock)
        case .askUserQuestion(let question):
            return .askUserQuestion(question)
        case .todoList(let todoList):
            return .todoList(todoList)
        case .fileChange(let fileChange):
            return .fileChange(fileChange)
        case .toolUse(let toolUse):
            return .toolUse(buildToolSnapshot(for: toolUse))
        case .subAgentActivity(let activity):
            return .subAgentActivity(buildSubAgentSnapshot(for: activity))
        case .error(let error):
            return .error(error)
        case .eventPayload(let payload):
            return .eventPayload(payload)
        }
    }

    private func buildTextSnapshot(
        for textContent: TextContent,
        isAssistantMessage: Bool
    ) -> TextRenderSnapshot {
        let key = TextArtifactKey(
            textID: textContent.id,
            textHash: textContent.text.hashValue,
            isAssistantMessage: isAssistantMessage
        )

        if let cached = textArtifactByKey[key] {
            return cached
        }

        let textBuildInterval = ChatPerformanceSignposts.beginInterval(
            "chat.snapshot.textBuild",
            "id=\(textContent.id.uuidString)"
        )

        let rawText = textContent.text
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        let snapshot: TextRenderSnapshot

        if trimmed.isEmpty || isProtocolArtifact(trimmed) {
            snapshot = TextRenderSnapshot(
                id: textContent.id,
                rawText: rawText,
                displayText: "",
                isAssistantMessage: isAssistantMessage,
                mode: .hiddenProtocolArtifact,
                parsedPlan: nil,
                tableAwareSegments: []
            )
        } else if isAssistantMessage, let parsedPlan = PlanModeMessageParser.parse(trimmed) {
            snapshot = TextRenderSnapshot(
                id: textContent.id,
                rawText: rawText,
                displayText: trimmed,
                isAssistantMessage: isAssistantMessage,
                mode: .planCard,
                parsedPlan: parsedPlan,
                tableAwareSegments: []
            )
        } else {
            let segments = MarkdownTableParser.parseContent(trimmed)
            let hasTable = segments.contains { segment in
                if case .table = segment {
                    return true
                }
                return false
            }

            if hasTable {
                snapshot = TextRenderSnapshot(
                    id: textContent.id,
                    rawText: rawText,
                    displayText: trimmed,
                    isAssistantMessage: isAssistantMessage,
                    mode: .tableAware,
                    parsedPlan: nil,
                    tableAwareSegments: makeTableAwareSegments(from: segments)
                )
            } else {
                snapshot = TextRenderSnapshot(
                    id: textContent.id,
                    rawText: rawText,
                    displayText: trimmed,
                    isAssistantMessage: isAssistantMessage,
                    mode: .markdown,
                    parsedPlan: nil,
                    tableAwareSegments: []
                )
            }
        }

        textArtifactByKey[key] = snapshot
        ChatPerformanceSignposts.endInterval(textBuildInterval, "mode=\(snapshot.mode)")

        return snapshot
    }

    private func makeTableAwareSegments(from segments: [TextContentSegment]) -> [TableAwareTextSegmentSnapshot] {
        segments.enumerated().map { index, segment in
            switch segment {
            case .table(let table):
                return TableAwareTextSegmentSnapshot(
                    id: "table-\(index)",
                    kind: .table,
                    headingText: nil,
                    text: nil,
                    table: MarkdownTableSnapshot(table: table)
                )
            case .text(let text):
                if let heading = SessionMarkdownTableTextLayout.headingText(from: text) {
                    return TableAwareTextSegmentSnapshot(
                        id: "heading-\(index)-\(heading.hashValue)",
                        kind: .heading,
                        headingText: heading,
                        text: nil,
                        table: nil
                    )
                }

                return TableAwareTextSegmentSnapshot(
                    id: "text-\(index)-\(text.hashValue)",
                    kind: .text,
                    headingText: nil,
                    text: text,
                    table: nil
                )
            }
        }
    }

    private func buildToolSnapshot(for toolUse: ToolUse) -> ToolRenderSnapshot {
        let key = ToolArtifactKey(
            toolID: toolUse.id,
            status: toolUse.status,
            inputHash: Self.stringSignature(toolUse.input),
            outputHash: Self.stringSignature(toolUse.output)
        )

        if let cached = toolArtifactByKey[key] {
            return cached
        }

        let toolInterval = ChatPerformanceSignposts.beginInterval(
            "chat.snapshot.toolBuild",
            "id=\(toolUse.id.uuidString)"
        )

        let parser = ToolInputParser(toolUse.input)
        let outputParser = ToolOutputParser(toolUse.output)

        let snapshot = ToolRenderSnapshot(
            id: toolUse.id,
            toolUse: toolUse,
            subtitle: parser.filePath
                ?? parser.pattern
                ?? parser.commandDescription
                ?? parser.command
                ?? parser.query
                ?? parser.url,
            detailLineCount: outputParser.lineCount,
            hasVisibleOutput: outputParser.hasVisibleContent
        )

        toolArtifactByKey[key] = snapshot
        ChatPerformanceSignposts.endInterval(toolInterval, "status=\(toolUse.status.rawValue)")
        return snapshot
    }

    private func buildSubAgentSnapshot(for activity: SubAgentActivity) -> SubAgentRenderSnapshot {
        let tools = activity.tools.map { toolUse in
            buildToolSnapshot(for: toolUse)
        }

        return SubAgentRenderSnapshot(
            id: activity.parentToolUseId,
            activity: activity,
            tools: tools
        )
    }

    private func buildToolHistoryEntrySnapshot(for entry: ToolHistoryEntry) -> ToolHistoryEntrySnapshot {
        let toolSnapshots = entry.tools.map { activeTool in
            buildActiveToolRenderSnapshot(for: activeTool)
        }

        let subAgentSnapshot: SubAgentRenderSnapshot?
        if let subAgent = entry.subAgent {
            let childToolSnapshots = subAgent.childTools.map { childTool in
                buildActiveToolRenderSnapshot(for: childTool)
            }
            let activity = SubAgentActivity(
                parentToolUseId: subAgent.id,
                subagentType: subAgent.subagentType,
                description: subAgent.description,
                tools: subAgent.childTools.map { $0.asToolUse() },
                status: subAgent.status
            )
            subAgentSnapshot = SubAgentRenderSnapshot(
                id: subAgent.id,
                activity: activity,
                tools: childToolSnapshots
            )
        } else {
            subAgentSnapshot = nil
        }

        return ToolHistoryEntrySnapshot(
            id: entry.id,
            afterMessageIndex: entry.afterMessageIndex,
            tools: toolSnapshots,
            subAgent: subAgentSnapshot
        )
    }

    private func buildActiveToolRenderSnapshot(for tool: ActiveTool) -> ToolRenderSnapshot {
        let toolUse = tool.asToolUse()
        return buildToolSnapshot(for: toolUse)
    }

    private func deduplicatedDisplayContent(for message: ChatMessage) -> [MessageContent] {
        var seenToolUseIDs: Set<String> = []
        var result: [MessageContent] = []

        for content in message.content.reversed() {
            if case .toolUse(let toolUse) = content,
               let toolUseID = toolUse.toolUseId {
                if seenToolUseIDs.contains(toolUseID) {
                    continue
                }
                seenToolUseIDs.insert(toolUseID)
            } else if case .subAgentActivity(let subAgent) = content {
                if seenToolUseIDs.contains(subAgent.parentToolUseId) {
                    continue
                }
                seenToolUseIDs.insert(subAgent.parentToolUseId)
            }
            result.append(content)
        }

        return Array(result.reversed())
    }

    private static func messageFingerprint(for message: ChatMessage) -> Int {
        var hasher = Hasher()
        hasher.combine(message.id)
        hasher.combine(message.role)
        hasher.combine(message.sequenceNumber)
        hasher.combine(message.isStreaming)
        hasher.combine(message.timestamp.timeIntervalSince1970)
        hasher.combine(message.content.count)

        for content in message.content {
            hasher.combine(lightweightContentFingerprint(content))
        }

        return hasher.finalize()
    }

    private static func lightweightContentFingerprint(_ content: MessageContent) -> Int {
        var hasher = Hasher()

        switch content {
        case .text(let text):
            hasher.combine(0)
            hasher.combine(text.id)
            hasher.combine(stringSignature(text.text))

        case .codeBlock(let codeBlock):
            hasher.combine(1)
            hasher.combine(codeBlock.id)
            hasher.combine(codeBlock.language)
            hasher.combine(stringSignature(codeBlock.code))
            hasher.combine(codeBlock.filename)

        case .askUserQuestion(let question):
            hasher.combine(2)
            hasher.combine(question.id)
            hasher.combine(question.question)
            hasher.combine(question.header)
            hasher.combine(question.options.count)
            hasher.combine(question.allowsMultiSelect)
            hasher.combine(question.allowsTextInput)
            hasher.combine(question.selectedOptions)
            hasher.combine(question.textResponse)
            for option in question.options {
                hasher.combine(option.id)
                hasher.combine(option.label)
                hasher.combine(option.description)
            }

        case .todoList(let todoList):
            hasher.combine(3)
            hasher.combine(todoList.id)
            hasher.combine(todoList.items.count)
            hasher.combine(todoList.sourceToolUseId)
            hasher.combine(todoList.parentToolUseId)
            for item in todoList.items {
                hasher.combine(item.id)
                hasher.combine(item.content)
                hasher.combine(item.status.rawValue)
            }

        case .fileChange(let fileChange):
            hasher.combine(4)
            hasher.combine(fileChange.id)
            hasher.combine(fileChange.filePath)
            hasher.combine(fileChange.changeType.rawValue)
            hasher.combine(fileChange.linesAdded)
            hasher.combine(fileChange.linesRemoved)
            hasher.combine(stringSignature(fileChange.diff))

        case .toolUse(let toolUse):
            hasher.combine(5)
            hasher.combine(toolSignature(toolUse))

        case .subAgentActivity(let activity):
            hasher.combine(6)
            hasher.combine(activity.id)
            hasher.combine(activity.parentToolUseId)
            hasher.combine(activity.subagentType)
            hasher.combine(activity.description)
            hasher.combine(activity.status.rawValue)
            hasher.combine(activity.tools.count)
            hasher.combine(stringSignature(activity.result))
            for tool in activity.tools {
                hasher.combine(toolSignature(tool))
            }

        case .error(let error):
            hasher.combine(7)
            hasher.combine(error.id)
            hasher.combine(error.message)
            hasher.combine(stringSignature(error.details))

        case .eventPayload(let payload):
            hasher.combine(8)
            hasher.combine(payload.id)
            hasher.combine(payload.eventType)
            hasher.combine(payload.data.count)
            for key in payload.data.keys.sorted() {
                hasher.combine(key)
                hasher.combine(String(describing: payload.data[key]?.value))
            }
        }

        return hasher.finalize()
    }

    private static func toolSignature(_ toolUse: ToolUse) -> Int {
        var hasher = Hasher()
        hasher.combine(toolUse.id)
        hasher.combine(toolUse.toolUseId)
        hasher.combine(toolUse.parentToolUseId)
        hasher.combine(toolUse.toolName)
        hasher.combine(toolUse.status.rawValue)
        hasher.combine(stringSignature(toolUse.input))
        hasher.combine(stringSignature(toolUse.output))
        return hasher.finalize()
    }

    private static func activeToolSignature(_ tool: ActiveTool) -> Int {
        var hasher = Hasher()
        hasher.combine(tool.id)
        hasher.combine(tool.name)
        hasher.combine(tool.status.rawValue)
        hasher.combine(stringSignature(tool.inputPreview))
        hasher.combine(stringSignature(tool.output))
        return hasher.finalize()
    }

    private static func stringSignature(_ value: String?) -> Int {
        value?.hashValue ?? 0
    }

    private func isProtocolArtifact(_ text: String) -> Bool {
        guard text.utf8.count <= 16_384 else { return false }
        guard text.hasPrefix("{"), text.hasSuffix("}"),
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = (json["type"] as? String)?.lowercased() else {
            return false
        }

        return ["user", "system", "assistant", "result", "tool_result"].contains(type)
    }
}
