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

    func color(_ colors: ThemeColors) -> Color {
        switch self {
        case .staged: return colors.diffAddition
        case .modified: return colors.fileModified
        case .untracked: return colors.fileUntracked
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
    let id: String
    let path: String
    let name: String
    let type: FileItemType
    var children: [FileItem]
    var isExpanded: Bool
    var gitStatus: GitFileStatus
    let isDirectory: Bool
    var childrenLoaded: Bool
    var hasChildrenHint: Bool

    init(
        path: String,
        name: String,
        type: FileItemType,
        children: [FileItem] = [],
        isExpanded: Bool = false,
        gitStatus: GitFileStatus = .unchanged,
        isDirectory: Bool,
        childrenLoaded: Bool = false,
        hasChildrenHint: Bool = false
    ) {
        self.id = path
        self.path = path
        self.name = name
        self.type = type
        self.children = children
        self.isExpanded = isExpanded
        self.gitStatus = gitStatus
        self.isDirectory = isDirectory
        self.childrenLoaded = childrenLoaded
        self.hasChildrenHint = hasChildrenHint
    }

    var hasChildren: Bool {
        guard isDirectory else { return false }
        if childrenLoaded {
            return !children.isEmpty
        }
        return hasChildrenHint
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

    func iconColor(_ colors: ThemeColors) -> Color {
        switch self {
        case .folder: return colors.gray666
        case .file: return colors.gray4A4
        case .gitFolder: return colors.gray666
        case .gitIgnore: return colors.textInactive
        case .license: return colors.gray4A4
        case .json: return colors.accentAmber
        case .yaml: return colors.textInactive
        case .typescript: return colors.accentAmber
        case .javascript: return colors.accentAmber
        case .swift: return colors.fileModified
        case .markdown: return colors.gray7A7
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
    case terminal = "Terminal"
    case output = "Output"
    case problems = "Problems"
    case scripts = "Scripts"

    var id: String { rawValue }
}
