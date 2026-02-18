#if DEBUG

import Foundation

enum SessionDetailPreviewScenario: String, CaseIterable, Identifiable {
    case fixtureMax
    case fixtureShort
    case emptyTimeline
    case textHeavySynthetic
    case toolHeavySynthetic

    var id: String { rawValue }

    var loadingTitle: String {
        switch self {
        case .fixtureMax:
            return "Loading Fixture Max..."
        case .fixtureShort:
            return "Loading Fixture Short..."
        case .emptyTimeline:
            return "Loading Empty Timeline..."
        case .textHeavySynthetic:
            return "Loading Text-Heavy Scenario..."
        case .toolHeavySynthetic:
            return "Loading Tool-Heavy Scenario..."
        }
    }
}

struct SessionDetailStatusVariants {
    let archived: SessionDetailPreviewData
    let error: SessionDetailPreviewData
}

enum SessionDetailPreviewScenarioBuilder {
    static func load(
        _ scenario: SessionDetailPreviewScenario,
        loader: SessionDetailFixtureLoader? = nil
    ) throws -> SessionDetailPreviewData {
        switch scenario {
        case .fixtureMax:
            return try loadFixtureMax(loader: loader)
        case .fixtureShort:
            return try loadFixtureShort(loader: loader)
        case .emptyTimeline:
            return try loadEmptyTimeline(loader: loader)
        case .textHeavySynthetic:
            return loadTextHeavySynthetic()
        case .toolHeavySynthetic:
            return loadToolHeavySynthetic()
        }
    }

    static func loadStatusVariants(
        loader: SessionDetailFixtureLoader? = nil
    ) throws -> SessionDetailStatusVariants {
        let fixtureLoader = try resolveLoader(loader)
        let fixtureData = try fixtureLoader.loadPreviewData()

        var archivedSession = fixtureData.session
        archivedSession.title = "Archived Session Preview"
        archivedSession.status = .archived
        archivedSession.lastAccessed = Date()

        var errorSession = fixtureData.session
        errorSession.title = "Error Session Preview"
        errorSession.status = .error
        errorSession.lastAccessed = Date()

        let errorMessages = Array(fixtureData.parsedMessages.suffix(min(48, fixtureData.parsedMessages.count)))
        let renderableErrorMessages = errorMessages.isEmpty ? toolHeavyMessages() : errorMessages

        return SessionDetailStatusVariants(
            archived: SessionDetailPreviewData(
                session: archivedSession,
                sourceMessageCount: fixtureData.sourceMessageCount,
                parsedMessages: fixtureData.parsedMessages
            ),
            error: SessionDetailPreviewData(
                session: errorSession,
                sourceMessageCount: renderableErrorMessages.count,
                parsedMessages: renderableErrorMessages
            )
        )
    }

    private static func loadFixtureMax(
        loader: SessionDetailFixtureLoader?
    ) throws -> SessionDetailPreviewData {
        let fixtureLoader = try resolveLoader(loader)
        return try fixtureLoader.loadPreviewData()
    }

    private static func loadFixtureShort(
        loader: SessionDetailFixtureLoader?
    ) throws -> SessionDetailPreviewData {
        let fixtureData = try loadFixtureMax(loader: loader)
        let shortCount = fixtureShortCount(total: fixtureData.parsedMessages.count)
        let shortMessages = Array(fixtureData.parsedMessages.prefix(shortCount))

        var shortSession = fixtureData.session
        shortSession.title = "\(fixtureData.session.displayTitle) (Short)"
        shortSession.lastAccessed = Date()

        return SessionDetailPreviewData(
            session: shortSession,
            sourceMessageCount: shortMessages.count,
            parsedMessages: shortMessages
        )
    }

    private static func loadEmptyTimeline(
        loader: SessionDetailFixtureLoader?
    ) throws -> SessionDetailPreviewData {
        let fixtureData = try loadFixtureMax(loader: loader)

        var emptySession = fixtureData.session
        emptySession.title = "\(fixtureData.session.displayTitle) (Empty)"
        emptySession.lastAccessed = Date()

        return SessionDetailPreviewData(
            session: emptySession,
            sourceMessageCount: fixtureData.sourceMessageCount,
            parsedMessages: []
        )
    }

    private static func loadTextHeavySynthetic() -> SessionDetailPreviewData {
        let messages = textHeavyMessages()

        return SessionDetailPreviewData(
            session: syntheticSession(title: "Session Detail Text Preview"),
            sourceMessageCount: messages.count,
            parsedMessages: messages
        )
    }

    private static func loadToolHeavySynthetic() -> SessionDetailPreviewData {
        let messages = toolHeavyMessages()

        return SessionDetailPreviewData(
            session: syntheticSession(title: "Session Detail Tool Preview"),
            sourceMessageCount: messages.count,
            parsedMessages: messages
        )
    }

    private static func resolveLoader(
        _ loader: SessionDetailFixtureLoader?
    ) throws -> SessionDetailFixtureLoader {
        if let loader {
            return loader
        }

        return try SessionDetailFixtureLoader()
    }

    private static func fixtureShortCount(total: Int) -> Int {
        guard total > 1 else { return total }

        var count = max(1, total / 4)
        count = min(count, 24)

        if count >= total {
            count = total - 1
        }

        return count
    }

    private static func syntheticSession(
        title: String,
        status: SessionStatus = .active
    ) -> Session {
        Session(
            repositoryId: SessionDetailFixtureLoader.previewRepositoryId,
            title: title,
            status: status,
            isWorktree: false,
            worktreePath: nil,
            createdAt: Date().addingTimeInterval(-7_200),
            lastAccessed: Date()
        )
    }

    private static func textHeavyMessages() -> [ChatMessage] {
        let extracted = PreviewData.chatMessages.compactMap { message -> ChatMessage? in
            guard message.role != .system else { return nil }

            let textContent = message.content.compactMap { content -> MessageContent? in
                guard case .text(let text) = content else { return nil }
                let trimmed = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return .text(TextContent(text: trimmed))
            }

            guard !textContent.isEmpty else { return nil }

            return ChatMessage(
                id: message.id,
                role: message.role,
                content: textContent,
                timestamp: message.timestamp,
                isStreaming: message.isStreaming,
                sequenceNumber: message.sequenceNumber
            )
        }

        if !extracted.isEmpty {
            return normalizeSequence(extracted)
        }

        return normalizeSequence([
            ChatMessage(role: .user, text: "Please summarize the parser behavior."),
            ChatMessage(
                role: .assistant,
                text: "The parser builds renderable timeline messages from daemon rows and preserves ordering."
            ),
        ])
    }

    private static func toolHeavyMessages() -> [ChatMessage] {
        let extracted = PreviewData.chatMessages.compactMap { message -> ChatMessage? in
            guard message.role == .assistant else { return nil }
            guard containsToolLikeContent(in: message.content) else { return nil }

            return ChatMessage(
                id: message.id,
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                isStreaming: message.isStreaming,
                sequenceNumber: message.sequenceNumber
            )
        }

        if !extracted.isEmpty {
            return normalizeSequence(extracted)
        }

        return normalizeSequence([
            ChatMessage(
                role: .assistant,
                content: [
                    .text(TextContent(text: "Running preview fallback tool pipeline.")),
                    .toolUse(
                        ToolUse(
                            toolUseId: "preview_tool_1",
                            toolName: "Read",
                            input: "{\"file_path\":\"SessionDetailView.swift\"}",
                            output: "Loaded 240 lines",
                            status: .completed
                        )
                    ),
                ],
                sequenceNumber: 1
            ),
            ChatMessage(
                role: .assistant,
                content: [
                    .subAgentActivity(
                        SubAgentActivity(
                            parentToolUseId: "preview_task_1",
                            subagentType: "Explore",
                            description: "Inspect session detail render states",
                            tools: [
                                ToolUse(
                                    toolUseId: "preview_child_1",
                                    parentToolUseId: "preview_task_1",
                                    toolName: "Grep",
                                    input: "{\"pattern\":\"sourceMessageCount\"}",
                                    output: "1 match",
                                    status: .completed
                                ),
                            ],
                            status: .completed,
                            result: "Render diagnostics complete"
                        )
                    ),
                    .subAgentActivity(
                        SubAgentActivity(
                            parentToolUseId: "preview_task_2",
                            subagentType: "Explore",
                            description: "Count parser fixtures",
                            tools: [
                                ToolUse(
                                    toolUseId: "preview_child_2",
                                    parentToolUseId: "preview_task_2",
                                    toolName: "Glob",
                                    input: "{\"pattern\":\"**/*fixture*.json\"}",
                                    output: "9 matches",
                                    status: .completed
                                ),
                            ],
                            status: .completed,
                            result: "Fixture inventory complete."
                        )
                    ),
                    .subAgentActivity(
                        SubAgentActivity(
                            parentToolUseId: "preview_task_3",
                            subagentType: "Explore",
                            description: "Locate missing merge tests",
                            tools: [
                                ToolUse(
                                    toolUseId: "preview_child_3",
                                    parentToolUseId: "preview_task_3",
                                    toolName: "Read",
                                    input: "{\"file_path\":\"SessionDetailMessageMapperTests.swift\"}",
                                    status: .running
                                ),
                            ],
                            status: .running
                        )
                    ),
                ],
                sequenceNumber: 2
            ),
        ])
    }

    private static func containsToolLikeContent(in content: [MessageContent]) -> Bool {
        content.contains { item in
            switch item {
            case .toolUse, .subAgentActivity:
                return true
            default:
                return false
            }
        }
    }

    private static func normalizeSequence(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.enumerated().map { index, message in
            ChatMessage(
                id: message.id,
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                isStreaming: message.isStreaming,
                sequenceNumber: index + 1
            )
        }
    }
}

#endif
