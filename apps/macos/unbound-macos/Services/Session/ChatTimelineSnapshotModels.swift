import ClaudeConversationTimeline
import Foundation

extension TableCellAlignment: Equatable {}

struct MarkdownTableSnapshot: Identifiable, Equatable {
    let id: String
    let headers: [String]
    let rows: [[String]]
    let alignments: [TableCellAlignment]

    init(table: MarkdownTable) {
        self.headers = table.headers
        self.rows = table.rows
        self.alignments = table.alignments

        var hasher = Hasher()
        hasher.combine(headers)
        hasher.combine(rows.count)
        for row in rows {
            hasher.combine(row)
        }
        hasher.combine(alignments.map { alignment in
            switch alignment {
            case .leading: return 0
            case .center: return 1
            case .trailing: return 2
            }
        })
        self.id = "tbl-\(hasher.finalize())"
    }

    func materialize() -> MarkdownTable {
        MarkdownTable(headers: headers, rows: rows, alignments: alignments)
    }
}

struct TableAwareTextSegmentSnapshot: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading
        case table
        case text
    }

    let id: String
    let kind: Kind
    let headingText: String?
    let text: String?
    let table: MarkdownTableSnapshot?
}

struct TextRenderSnapshot: Identifiable, Equatable {
    enum Mode: Equatable {
        case hiddenProtocolArtifact
        case markdown
        case tableAware
        case planCard
    }

    let id: UUID
    let rawText: String
    let displayText: String
    let isAssistantMessage: Bool
    let mode: Mode
    let parsedPlan: PlanModeMessageParser.ParsedPlan?
    let tableAwareSegments: [TableAwareTextSegmentSnapshot]
}

struct ToolRenderSnapshot: Identifiable, Equatable {
    let id: UUID
    let toolUse: ToolUse
    let subtitle: String?
    let detailLineCount: Int
    let hasVisibleOutput: Bool
}

struct SubAgentRenderSnapshot: Identifiable, Equatable {
    let id: String
    let activity: SubAgentActivity
    let tools: [ToolRenderSnapshot]
}

struct ToolHistoryEntrySnapshot: Identifiable, Equatable {
    let id: UUID
    let afterMessageIndex: Int
    let tools: [ToolRenderSnapshot]
    let subAgent: SubAgentRenderSnapshot?

    static func == (lhs: ToolHistoryEntrySnapshot, rhs: ToolHistoryEntrySnapshot) -> Bool {
        lhs.id == rhs.id
            && lhs.afterMessageIndex == rhs.afterMessageIndex
            && lhs.tools.map(\.id) == rhs.tools.map(\.id)
            && lhs.subAgent?.id == rhs.subAgent?.id
    }
}

struct FileChangeSummarySnapshot: Equatable {
    let files: [FileChange]
    let totalLinesAdded: Int
    let totalLinesRemoved: Int

    static let empty = FileChangeSummarySnapshot(
        files: [],
        totalLinesAdded: 0,
        totalLinesRemoved: 0
    )
}

enum MessageContentSnapshot: Identifiable, Equatable {
    case text(TextRenderSnapshot)
    case codeBlock(CodeBlock)
    case askUserQuestion(AskUserQuestion)
    case todoList(TodoList)
    case fileChange(FileChange)
    case toolUse(ToolRenderSnapshot)
    case subAgentActivity(SubAgentRenderSnapshot)
    case error(ErrorContent)
    case eventPayload(EventPayload)

    var id: UUID {
        switch self {
        case .text(let snapshot):
            return snapshot.id
        case .codeBlock(let content):
            return content.id
        case .askUserQuestion(let question):
            return question.id
        case .todoList(let todo):
            return todo.id
        case .fileChange(let fileChange):
            return fileChange.id
        case .toolUse(let tool):
            return tool.id
        case .subAgentActivity(let subAgent):
            return subAgent.activity.id
        case .error(let error):
            return error.id
        case .eventPayload(let payload):
            return payload.id
        }
    }
}

enum ChatRenderableBlockSnapshot: Identifiable, Equatable {
    case content(MessageContentSnapshot)
    case standaloneTools([ToolRenderSnapshot])
    case parallelAgents([SubAgentRenderSnapshot])

    var id: String {
        switch self {
        case .content(let content):
            return "content:\(content.id.uuidString)"
        case .standaloneTools(let tools):
            let identity = tools.map { $0.toolUse.toolUseId ?? $0.id.uuidString }.joined(separator: "|")
            return "tools:\(identity)"
        case .parallelAgents(let activities):
            let identity = activities.map(\.id).joined(separator: "|")
            return "parallel:\(identity)"
        }
    }
}

struct ChatMessageRowSnapshot: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let timestamp: Date
    let sequenceNumber: Int
    let isStreaming: Bool
    let renderKey: Int
    let blocks: [ChatRenderableBlockSnapshot]
    let fileChangeSummary: FileChangeSummarySnapshot
}

struct ChatTimelineSnapshot: Equatable {
    let revision: Int
    let rows: [ChatMessageRowSnapshot]
    let toolHistory: [ToolHistoryEntry]
    let activeSubAgents: [ActiveSubAgent]
    let activeTools: [ActiveTool]
    let streamingRow: ChatMessageRowSnapshot?

    // Pre-computed derived state
    let toolHistoryByIndex: [Int: [ToolHistoryEntry]]
    let rowIDs: [UUID]
    let scrollIdentity: Int
    let renderedMessageCount: Int
    let hasActiveToolState: Bool
    let isEmpty: Bool

    // Pre-computed tool history and active tool render snapshots
    let toolHistorySnapshots: [ToolHistoryEntrySnapshot]
    let toolHistorySnapshotsByIndex: [Int: [ToolHistoryEntrySnapshot]]
    let activeToolRenderSnapshots: [ToolRenderSnapshot]

    // Performance metadata (excluded from equality)
    let publishedAt: CFAbsoluteTime

    static let empty = ChatTimelineSnapshot(
        revision: 0,
        rows: [],
        toolHistory: [],
        activeSubAgents: [],
        activeTools: [],
        streamingRow: nil,
        toolHistoryByIndex: [:],
        rowIDs: [],
        scrollIdentity: 0,
        renderedMessageCount: 0,
        hasActiveToolState: false,
        isEmpty: true,
        toolHistorySnapshots: [],
        toolHistorySnapshotsByIndex: [:],
        activeToolRenderSnapshots: [],
        publishedAt: 0
    )

    static func == (lhs: ChatTimelineSnapshot, rhs: ChatTimelineSnapshot) -> Bool {
        lhs.revision == rhs.revision &&
        lhs.rows == rhs.rows &&
        lhs.streamingRow == rhs.streamingRow &&
        lhs.toolHistory.map(\.id) == rhs.toolHistory.map(\.id) &&
        lhs.activeSubAgents.map(\.id) == rhs.activeSubAgents.map(\.id) &&
        lhs.activeTools.map(\.id) == rhs.activeTools.map(\.id)
    }
}
