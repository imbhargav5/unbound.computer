//
//  SessionContentBlock.swift
//  unbound-ios
//
//  Parsed content blocks for session detail messages.
//

import Foundation

struct SessionToolUse: Identifiable, Hashable {
    let id: UUID
    let toolUseId: String?
    let parentToolUseId: String?
    let toolName: String
    let summary: String

    init(
        id: UUID = UUID(),
        toolUseId: String? = nil,
        parentToolUseId: String? = nil,
        toolName: String,
        summary: String
    ) {
        self.id = id
        self.toolUseId = toolUseId
        self.parentToolUseId = parentToolUseId
        self.toolName = toolName
        self.summary = summary
    }

    var icon: String {
        switch toolName {
        case "Read": return "doc.text"
        case "Write": return "square.and.pencil"
        case "Edit": return "pencil"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder"
        case "Bash": return "terminal"
        case "WebFetch": return "globe"
        case "WebSearch": return "magnifyingglass.circle"
        case "Task": return "checklist"
        case "NotebookEdit": return "book"
        default: return "gearshape"
        }
    }
}

struct SessionSubAgentActivity: Identifiable, Hashable {
    let id: UUID
    let parentToolUseId: String
    let subagentType: String
    let description: String
    var tools: [SessionToolUse]

    init(
        id: UUID = UUID(),
        parentToolUseId: String,
        subagentType: String,
        description: String,
        tools: [SessionToolUse] = []
    ) {
        self.id = id
        self.parentToolUseId = parentToolUseId
        self.subagentType = subagentType
        self.description = description
        self.tools = tools
    }

    var displayName: String {
        switch subagentType.lowercased() {
        case "explore":
            return "Explore Agent"
        case "plan":
            return "Plan Agent"
        case "bash":
            return "Bash Agent"
        case "general-purpose":
            return "General Purpose Agent"
        default:
            return "\(subagentType) Agent"
        }
    }

    var icon: String {
        switch subagentType.lowercased() {
        case "explore":
            return "binoculars.fill"
        case "plan":
            return "list.bullet.clipboard.fill"
        case "bash":
            return "terminal.fill"
        case "general-purpose":
            return "cpu.fill"
        default:
            return "cpu.fill"
        }
    }
}

enum SessionContentBlock: Identifiable, Hashable {
    case text(String)
    case toolUse(SessionToolUse)
    case subAgentActivity(SessionSubAgentActivity)
    case error(String)

    var id: Int { hashValue }

    var isVisibleContent: Bool {
        switch self {
        case .text(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .toolUse, .subAgentActivity:
            return true
        case .error(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
