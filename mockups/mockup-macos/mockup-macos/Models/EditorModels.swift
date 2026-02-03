//
//  EditorModels.swift
//  mockup-macos
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
    let content: String?
    let language: String?

    init(
        id: UUID = UUID(),
        kind: EditorTabKind,
        path: String,
        content: String? = nil,
        language: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.content = content
        self.language = language
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
