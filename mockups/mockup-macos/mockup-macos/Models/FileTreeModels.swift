//
//  FileTreeModels.swift
//  mockup-macos
//
//  Models for file tree display
//

import Foundation

// MARK: - File Item

struct FileItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: FileType
    var children: [FileItem]?
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        name: String,
        type: FileType,
        children: [FileItem]? = nil,
        isExpanded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.children = children
        self.isExpanded = isExpanded
    }

    var isDirectory: Bool {
        type == .folder || type == .gitFolder
    }

    var iconName: String {
        type.iconName
    }
}

// MARK: - File Type

enum FileType: String, Hashable {
    case folder
    case file
    case markdown
    case swift
    case typescript
    case javascript
    case json
    case yaml
    case gitFolder
    case gitIgnore
    case license

    var iconName: String {
        switch self {
        case .folder: return "folder"
        case .file: return "doc"
        case .markdown: return "doc.text"
        case .swift: return "swift"
        case .typescript, .javascript: return "curlybraces"
        case .json: return "doc.badge.gearshape"
        case .yaml: return "doc.text"
        case .gitFolder: return "folder.badge.gearshape"
        case .gitIgnore: return "eye.slash"
        case .license: return "doc.badge.ellipsis"
        }
    }
}

// MARK: - Git Status File

struct GitStatusFile: Identifiable, Hashable {
    let id: UUID
    let path: String
    let status: FileStatus
    let staged: Bool

    init(
        id: UUID = UUID(),
        path: String,
        status: FileStatus,
        staged: Bool = false
    ) {
        self.id = id
        self.path = path
        self.status = status
        self.staged = staged
    }

    var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

// MARK: - Git Commit

struct GitCommit: Identifiable, Hashable {
    let id: UUID
    let hash: String
    let shortHash: String
    let message: String
    let author: String
    let date: Date

    init(
        id: UUID = UUID(),
        hash: String,
        shortHash: String? = nil,
        message: String,
        author: String,
        date: Date = Date()
    ) {
        self.id = id
        self.hash = hash
        self.shortHash = shortHash ?? String(hash.prefix(7))
        self.message = message
        self.author = author
        self.date = date
    }
}
