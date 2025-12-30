import Foundation
import SwiftUI

/// Represents different types of rich content that can appear in chat messages
enum ChatContent: Identifiable, Hashable {
    case text(String)
    case mcqQuestion(MCQQuestion)
    case toolUsage(ToolUsageState)
    case codeDiff(CodeDiff)

    var id: String {
        switch self {
        case .text(let text):
            return "text-\(text.hashValue)"
        case .mcqQuestion(let q):
            return q.id.uuidString
        case .toolUsage(let t):
            return t.id.uuidString
        case .codeDiff(let d):
            return d.id.uuidString
        }
    }
}

// MARK: - MCQ Question

/// MCQ Question following Claude Code's AskUserQuestion pattern
struct MCQQuestion: Identifiable, Hashable {
    let id: UUID
    let question: String
    let options: [MCQOption]
    var selectedOptionId: UUID?
    var customAnswer: String?  // For "Something else" option
    var isConfirmed: Bool = false

    var isAnswered: Bool { isConfirmed && (selectedOptionId != nil || customAnswer != nil) }
    var hasCustomAnswer: Bool { customAnswer != nil && !customAnswer!.isEmpty }

    struct MCQOption: Identifiable, Hashable {
        let id: UUID
        let label: String
        let description: String?
        let icon: String?  // SF Symbol name
        let isCustomOption: Bool  // True for "Something else"

        init(id: UUID = UUID(), label: String, description: String? = nil, icon: String? = nil, isCustomOption: Bool = false) {
            self.id = id
            self.label = label
            self.description = description
            self.icon = icon
            self.isCustomOption = isCustomOption
        }
    }

    init(id: UUID = UUID(), question: String, options: [MCQOption], selectedOptionId: UUID? = nil, customAnswer: String? = nil, isConfirmed: Bool = false) {
        self.id = id
        self.question = question
        self.options = options
        self.selectedOptionId = selectedOptionId
        self.customAnswer = customAnswer
        self.isConfirmed = isConfirmed
    }

    /// Static helper to create the "Something else" option
    static let somethingElseOption = MCQOption(
        label: "Something else",
        description: "Type your own answer",
        icon: "text.bubble",
        isCustomOption: true
    )
}

// MARK: - Tool Usage State

/// Tool usage state for loading indicators (simulates Claude Code's tool execution)
struct ToolUsageState: Identifiable, Hashable {
    let id: UUID
    var toolName: String
    var statusText: String
    var isActive: Bool
    var progress: Double?

    init(id: UUID = UUID(), toolName: String, statusText: String, isActive: Bool = true, progress: Double? = nil) {
        self.id = id
        self.toolName = toolName
        self.statusText = statusText
        self.isActive = isActive
        self.progress = progress
    }

    /// Pre-defined tool types for consistent styling
    enum ToolType: String, CaseIterable {
        case read = "Read"
        case write = "Write"
        case edit = "Edit"
        case grep = "Grep"
        case glob = "Glob"
        case bash = "Bash"
        case webFetch = "WebFetch"
        case task = "Task"

        var icon: String {
            switch self {
            case .read: return "doc.text"
            case .write: return "square.and.pencil"
            case .edit: return "pencil"
            case .grep: return "magnifyingglass"
            case .glob: return "folder"
            case .bash: return "terminal"
            case .webFetch: return "globe"
            case .task: return "checklist"
            }
        }
    }

    var toolType: ToolType? {
        ToolType(rawValue: toolName)
    }

    var icon: String {
        toolType?.icon ?? "gearshape"
    }
}

// MARK: - Code Diff

/// Code diff representation for showing generated/modified code
struct CodeDiff: Identifiable, Hashable {
    let id: UUID
    let filename: String
    let language: String
    var hunks: [DiffHunk]
    var isExpanded: Bool

    init(id: UUID = UUID(), filename: String, language: String, hunks: [DiffHunk], isExpanded: Bool = true) {
        self.id = id
        self.filename = filename
        self.language = language
        self.hunks = hunks
        self.isExpanded = isExpanded
    }

    struct DiffHunk: Identifiable, Hashable {
        let id: UUID
        let header: String?  // e.g., "@@ -10,5 +10,7 @@"
        let lines: [DiffLine]

        init(id: UUID = UUID(), header: String? = nil, lines: [DiffLine]) {
            self.id = id
            self.header = header
            self.lines = lines
        }
    }

    struct DiffLine: Identifiable, Hashable {
        let id: UUID
        let content: String
        let type: LineType
        let lineNumber: Int?

        init(id: UUID = UUID(), content: String, type: LineType, lineNumber: Int? = nil) {
            self.id = id
            self.content = content
            self.type = type
            self.lineNumber = lineNumber
        }

        enum LineType: String {
            case addition = "+"
            case deletion = "-"
            case context = " "
        }
    }

    /// Creates diff lines from raw diff text
    static func parseDiffLines(_ text: String, startingLine: Int = 1) -> [DiffLine] {
        var lines: [DiffLine] = []
        var lineNum = startingLine

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            let type: DiffLine.LineType
            let content: String

            if lineStr.hasPrefix("+") {
                type = .addition
                content = String(lineStr.dropFirst())
            } else if lineStr.hasPrefix("-") {
                type = .deletion
                content = String(lineStr.dropFirst())
            } else {
                type = .context
                content = lineStr.hasPrefix(" ") ? String(lineStr.dropFirst()) : lineStr
            }

            lines.append(DiffLine(content: content, type: type, lineNumber: lineNum))
            lineNum += 1
        }

        return lines
    }
}
