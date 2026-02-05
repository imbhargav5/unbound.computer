//
//  EditorModels.swift
//  unbound-macos
//
//  Models for editor tabs and diff loading state.
//

import Foundation

enum EditorTabKind: String, Hashable {
    case file
    case diff
}

struct EditorTab: Identifiable, Hashable {
    let id: UUID
    let kind: EditorTabKind
    let path: String
    let fullPath: String?
    let sessionId: UUID?

    init(
        id: UUID = UUID(),
        kind: EditorTabKind,
        path: String,
        fullPath: String? = nil,
        sessionId: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.fullPath = fullPath
        self.sessionId = sessionId
    }

    var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }
}

struct DiffLoadState: Hashable {
    var isLoading: Bool = false
    var diff: FileDiff?
    var errorMessage: String?
}
