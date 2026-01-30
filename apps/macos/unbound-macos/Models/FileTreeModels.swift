//
//  FileTreeModels.swift
//  unbound-macos
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import SwiftUI

// MARK: - Git File Status

enum GitFileStatus: String, Hashable {
    case staged
    case modified
    case untracked
    case unchanged

    var color: Color {
        switch self {
        case .staged: return .green
        case .modified: return .orange
        case .untracked: return .gray
        case .unchanged: return .clear
        }
    }

    var indicator: String {
        switch self {
        case .staged: return "A"
        case .modified: return "M"
        case .untracked: return "?"
        case .unchanged: return ""
        }
    }
}

// MARK: - File Item

struct FileItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: FileItemType
    var children: [FileItem]
    var isExpanded: Bool
    var gitStatus: GitFileStatus

    init(
        id: UUID = UUID(),
        name: String,
        type: FileItemType,
        children: [FileItem] = [],
        isExpanded: Bool = false,
        gitStatus: GitFileStatus = .unchanged
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.children = children
        self.isExpanded = isExpanded
        self.gitStatus = gitStatus
    }

    var hasChildren: Bool {
        !children.isEmpty
    }
}

// MARK: - File Item Type

enum FileItemType: String, Hashable {
    case folder
    case file
    case gitFolder
    case gitIgnore
    case license
    case json
    case yaml
    case typescript
    case javascript
    case swift
    case markdown

    var iconName: String {
        switch self {
        case .folder: return "folder.fill"
        case .file: return "doc.fill"
        case .gitFolder: return "folder.fill"
        case .gitIgnore: return "eye.slash.fill"
        case .license: return "doc.text.fill"
        case .json: return "curlybraces"
        case .yaml: return "doc.text.fill"
        case .typescript: return "t.square.fill"
        case .javascript: return "j.square.fill"
        case .swift: return "swift"
        case .markdown: return "doc.richtext.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .folder: return .blue
        case .file: return .secondary
        case .gitFolder: return .gray
        case .gitIgnore: return .red
        case .license: return .secondary
        case .json: return .yellow
        case .yaml: return .red
        case .typescript: return .blue
        case .javascript: return .yellow
        case .swift: return .orange
        case .markdown: return .purple
        }
    }

    static func fromExtension(_ ext: String) -> FileItemType {
        switch ext.lowercased() {
        case "swift": return .swift
        case "ts", "tsx": return .typescript
        case "js", "jsx": return .javascript
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "md", "markdown": return .markdown
        case "gitignore": return .gitIgnore
        case "license": return .license
        default: return .file
        }
    }
}

// MARK: - Version Control Tab

enum VersionControlTab: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case allFiles = "All files"

    var id: String { rawValue }
}

// MARK: - Terminal Tab

enum TerminalTab: String, CaseIterable, Identifiable {
    case run = "Run"
    case terminal = "Terminal"

    var id: String { rawValue }
}
