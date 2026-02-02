//
//  DiffModels.swift
//  unbound-macos
//
//  Models for representing parsed git diffs
//  Inspired by @pierre/diffs library features
//

import Foundation
import SwiftUI

// MARK: - Diff View Mode

/// Display mode for diff viewer
enum DiffViewMode: String, CaseIterable, Identifiable {
    case unified = "Unified"
    case split = "Split"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .unified: return "text.alignleft"
        case .split: return "rectangle.split.2x1"
        }
    }
}

// MARK: - Diff Line Type

/// Type of line in a diff
enum DiffLineType: String, Hashable, Codable {
    case context    // Unchanged line (starts with space)
    case addition   // Added line (starts with +)
    case deletion   // Removed line (starts with -)
    case header     // Hunk header (@@ -x,y +a,b @@)

    var prefix: String {
        switch self {
        case .context: return " "
        case .addition: return "+"
        case .deletion: return "-"
        case .header: return "@@"
        }
    }
}

// MARK: - Diff Line

/// A single line in a diff
struct DiffLine: Identifiable, Hashable {
    let id: UUID
    let type: DiffLineType
    let content: String
    let oldLineNumber: Int?  // Line number in old file (nil for additions)
    let newLineNumber: Int?  // Line number in new file (nil for deletions)

    init(
        id: UUID = UUID(),
        type: DiffLineType,
        content: String,
        oldLineNumber: Int? = nil,
        newLineNumber: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

// MARK: - Diff Hunk

/// A hunk (section) of changes in a diff
struct DiffHunk: Identifiable, Hashable {
    let id: UUID
    let oldStart: Int      // Starting line in old file
    let oldCount: Int      // Number of lines from old file
    let newStart: Int      // Starting line in new file
    let newCount: Int      // Number of lines in new file
    let context: String?   // Optional context (function name, etc.)
    let lines: [DiffLine]

    init(
        id: UUID = UUID(),
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        context: String? = nil,
        lines: [DiffLine] = []
    ) {
        self.id = id
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.context = context
        self.lines = lines
    }

    /// Header string for this hunk
    var headerString: String {
        var header = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        if let context = context, !context.isEmpty {
            header += " \(context)"
        }
        return header
    }
}

// MARK: - File Diff

/// Complete diff for a single file
struct FileDiff: Identifiable, Hashable {
    let id: UUID
    let filePath: String
    let oldPath: String?           // For renames, the original path
    let changeType: FileChangeType
    let hunks: [DiffHunk]
    let linesAdded: Int
    let linesRemoved: Int
    let isBinary: Bool

    init(
        id: UUID = UUID(),
        filePath: String,
        oldPath: String? = nil,
        changeType: FileChangeType = .modified,
        hunks: [DiffHunk] = [],
        linesAdded: Int = 0,
        linesRemoved: Int = 0,
        isBinary: Bool = false
    ) {
        self.id = id
        self.filePath = filePath
        self.oldPath = oldPath
        self.changeType = changeType
        self.hunks = hunks
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.isBinary = isBinary
    }

    /// Total number of changes (additions + deletions)
    var totalChanges: Int {
        linesAdded + linesRemoved
    }

    /// Check if this is a rename
    var isRename: Bool {
        oldPath != nil && oldPath != filePath
    }

    /// Parse a single file diff from raw diff content.
    /// Convenience wrapper around DiffParser.parseFileDiff.
    static func parse(from content: String, filePath: String) -> FileDiff? {
        DiffParser.parseFileDiff(content, filePath: filePath)
    }
}

// MARK: - Git Status With Diffs

/// Enhanced git status that includes diff data
struct GitStatusWithDiffs {
    let branch: String
    let isClean: Bool
    let staged: [FileDiff]
    let unstaged: [FileDiff]
    let untracked: [String]

    /// All files with changes (staged + unstaged)
    var allChanges: [FileDiff] {
        staged + unstaged
    }

    /// Total lines added across all files
    var totalLinesAdded: Int {
        allChanges.reduce(0) { $0 + $1.linesAdded }
    }

    /// Total lines removed across all files
    var totalLinesRemoved: Int {
        allChanges.reduce(0) { $0 + $1.linesRemoved }
    }
}

// MARK: - Diff Statistics

/// Lightweight diff stats for a file (without full diff content)
struct FileDiffStats: Identifiable, Hashable {
    let id: UUID
    let filePath: String
    let linesAdded: Int
    let linesRemoved: Int
    let changeType: FileChangeType

    init(
        id: UUID = UUID(),
        filePath: String,
        linesAdded: Int,
        linesRemoved: Int,
        changeType: FileChangeType = .modified
    ) {
        self.id = id
        self.filePath = filePath
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.changeType = changeType
    }
}

// MARK: - Diff Colors Extension

extension DiffLineType {
    /// Background color for this line type
    func backgroundColor(colors: ThemeColors) -> Color {
        switch self {
        case .addition:
            return colors.success.opacity(0.15)
        case .deletion:
            return colors.destructive.opacity(0.15)
        case .header:
            return colors.info.opacity(0.1)
        case .context:
            return Color.clear
        }
    }

    /// Gutter/indicator color for this line type
    func gutterColor(colors: ThemeColors) -> Color {
        switch self {
        case .addition:
            return colors.success
        case .deletion:
            return colors.destructive
        case .header:
            return colors.info
        case .context:
            return colors.mutedForeground
        }
    }

    /// Text color for this line type
    func textColor(colors: ThemeColors) -> Color {
        switch self {
        case .header:
            return colors.info
        default:
            return colors.foreground
        }
    }
}
