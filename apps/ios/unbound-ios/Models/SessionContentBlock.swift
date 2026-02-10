//
//  SessionContentBlock.swift
//  unbound-ios
//
//  Parsed content blocks for session detail messages.
//

import Foundation

struct SessionToolUse: Identifiable, Hashable {
    let id: UUID
    let toolName: String
    let summary: String

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

enum SessionContentBlock: Identifiable, Hashable {
    case text(String)
    case toolUse(SessionToolUse)
    case error(String)

    var id: Int { hashValue }

    var isVisibleContent: Bool {
        switch self {
        case .text(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .toolUse:
            return true
        case .error(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
