//
//  DiffParser.swift
//  unbound-macos
//
//  Parses unified diff format into structured models
//

import Foundation

// MARK: - Diff Parser

class DiffParser {

    // MARK: - Public API

    /// Parse raw git diff output into structured FileDiff objects
    /// - Parameter rawDiff: The raw output from `git diff`
    /// - Returns: Array of parsed file diffs
    static func parse(_ rawDiff: String) -> [FileDiff] {
        guard !rawDiff.isEmpty else { return [] }

        var fileDiffs: [FileDiff] = []
        let fileSections = splitIntoFileSections(rawDiff)

        for section in fileSections {
            if let fileDiff = parseFileSection(section) {
                fileDiffs.append(fileDiff)
            }
        }

        return fileDiffs
    }

    /// Parse a single file's diff content
    /// - Parameters:
    ///   - content: Raw diff content for a single file
    ///   - filePath: The file path (used if not extractable from diff)
    /// - Returns: Parsed FileDiff or nil if parsing fails
    static func parseFileDiff(_ content: String, filePath: String) -> FileDiff? {
        let lines = content.components(separatedBy: "\n")
        let hunks = parseHunks(from: lines)

        // Calculate stats
        var linesAdded = 0
        var linesRemoved = 0

        for hunk in hunks {
            for line in hunk.lines {
                switch line.type {
                case .addition: linesAdded += 1
                case .deletion: linesRemoved += 1
                default: break
                }
            }
        }

        // Detect change type
        let changeType = detectChangeType(from: lines, linesAdded: linesAdded, linesRemoved: linesRemoved)

        return FileDiff(
            filePath: filePath,
            changeType: changeType,
            hunks: hunks,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            isBinary: content.contains("Binary files")
        )
    }

    /// Parse git diff --stat output for quick statistics
    /// - Parameter statOutput: Output from `git diff --stat`
    /// - Returns: Array of file stats
    static func parseStats(_ statOutput: String) -> [FileDiffStats] {
        var stats: [FileDiffStats] = []
        let lines = statOutput.components(separatedBy: "\n")

        for line in lines {
            // Match pattern like: "file.swift | 10 ++++----"
            // or: "file.swift | 5 ++"
            // or: "file.swift | Bin 0 -> 1234 bytes"
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard line.contains("|") else { continue }

            let parts = line.components(separatedBy: "|")
            guard parts.count >= 2 else { continue }

            let filePath = parts[0].trimmingCharacters(in: .whitespaces)
            let statsString = parts[1].trimmingCharacters(in: .whitespaces)

            // Skip summary line (e.g., "3 files changed, 10 insertions(+), 5 deletions(-)")
            if filePath.contains("files changed") || filePath.contains("file changed") {
                continue
            }

            // Parse the +/- counts
            let (added, removed) = parseStatCounts(statsString)

            // Detect change type based on stats
            let changeType: FileChangeType
            if removed == 0 && added > 0 {
                changeType = .created
            } else if added == 0 && removed > 0 {
                changeType = .deleted
            } else {
                changeType = .modified
            }

            stats.append(FileDiffStats(
                filePath: filePath,
                linesAdded: added,
                linesRemoved: removed,
                changeType: changeType
            ))
        }

        return stats
    }

    // MARK: - Private Helpers

    /// Split raw diff into sections per file
    private static func splitIntoFileSections(_ rawDiff: String) -> [String] {
        // Split by "diff --git" markers
        let pattern = "diff --git"
        var sections: [String] = []

        let components = rawDiff.components(separatedBy: pattern)

        for (index, component) in components.enumerated() {
            // Skip empty first component
            if index == 0 && component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            // Re-add the marker for proper parsing
            let section = index == 0 ? component : pattern + component
            if !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append(section)
            }
        }

        return sections
    }

    /// Parse a single file section
    private static func parseFileSection(_ section: String) -> FileDiff? {
        let lines = section.components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        // Extract file paths
        var filePath: String?
        var oldPath: String?

        for line in lines {
            // Check for "diff --git a/path b/path"
            if line.hasPrefix("diff --git") {
                let paths = extractPathsFromDiffLine(line)
                oldPath = paths.old
                filePath = paths.new
            }
            // Check for "+++ b/path" (new file path)
            else if line.hasPrefix("+++ ") {
                let path = String(line.dropFirst(4))
                if path.hasPrefix("b/") {
                    filePath = String(path.dropFirst(2))
                } else if path != "/dev/null" {
                    filePath = path
                }
            }
            // Check for "--- a/path" (old file path)
            else if line.hasPrefix("--- ") {
                let path = String(line.dropFirst(4))
                if path.hasPrefix("a/") {
                    oldPath = String(path.dropFirst(2))
                } else if path != "/dev/null" {
                    oldPath = path
                }
            }
        }

        guard let path = filePath ?? oldPath else { return nil }

        // Parse hunks
        let hunks = parseHunks(from: lines)

        // Calculate stats
        var linesAdded = 0
        var linesRemoved = 0

        for hunk in hunks {
            for line in hunk.lines {
                switch line.type {
                case .addition: linesAdded += 1
                case .deletion: linesRemoved += 1
                default: break
                }
            }
        }

        // Detect change type
        let changeType = detectChangeType(from: lines, linesAdded: linesAdded, linesRemoved: linesRemoved)

        // Check for binary
        let isBinary = section.contains("Binary files") || section.contains("GIT binary patch")

        return FileDiff(
            filePath: path,
            oldPath: oldPath != path ? oldPath : nil,
            changeType: changeType,
            hunks: hunks,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            isBinary: isBinary
        )
    }

    /// Extract old and new paths from "diff --git a/path b/path" line
    private static func extractPathsFromDiffLine(_ line: String) -> (old: String?, new: String?) {
        // Pattern: diff --git a/old/path b/new/path
        let withoutPrefix = line.replacingOccurrences(of: "diff --git ", with: "")

        // Find the split point - look for " b/" pattern
        if let range = withoutPrefix.range(of: " b/") {
            let oldPart = String(withoutPrefix[..<range.lowerBound])
            let newPart = String(withoutPrefix[range.upperBound...])

            let oldPath = oldPart.hasPrefix("a/") ? String(oldPart.dropFirst(2)) : oldPart
            return (oldPath, newPart)
        }

        return (nil, nil)
    }

    /// Parse hunks from diff lines
    private static func parseHunks(from lines: [String]) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentHunk: (header: (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, context: String?), lines: [DiffLine])?
        var oldLineNum = 0
        var newLineNum = 0

        for line in lines {
            // Check for hunk header
            if line.hasPrefix("@@") {
                // Save previous hunk if exists
                if let hunk = currentHunk {
                    hunks.append(DiffHunk(
                        oldStart: hunk.header.oldStart,
                        oldCount: hunk.header.oldCount,
                        newStart: hunk.header.newStart,
                        newCount: hunk.header.newCount,
                        context: hunk.header.context,
                        lines: hunk.lines
                    ))
                }

                // Parse new hunk header
                if let header = parseHunkHeader(line) {
                    currentHunk = (header, [])
                    oldLineNum = header.oldStart
                    newLineNum = header.newStart
                }
            }
            // Process diff content lines
            else if currentHunk != nil {
                let diffLine: DiffLine?

                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    // Addition
                    let content = String(line.dropFirst())
                    diffLine = DiffLine(
                        type: .addition,
                        content: content,
                        oldLineNumber: nil,
                        newLineNumber: newLineNum
                    )
                    newLineNum += 1
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    // Deletion
                    let content = String(line.dropFirst())
                    diffLine = DiffLine(
                        type: .deletion,
                        content: content,
                        oldLineNumber: oldLineNum,
                        newLineNumber: nil
                    )
                    oldLineNum += 1
                } else if line.hasPrefix(" ") || (currentHunk!.lines.isEmpty == false && !line.hasPrefix("\\")) {
                    // Context line (or continuation)
                    let content = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                    diffLine = DiffLine(
                        type: .context,
                        content: content,
                        oldLineNumber: oldLineNum,
                        newLineNumber: newLineNum
                    )
                    oldLineNum += 1
                    newLineNum += 1
                } else {
                    diffLine = nil
                }

                if let dl = diffLine {
                    currentHunk?.lines.append(dl)
                }
            }
        }

        // Don't forget the last hunk
        if let hunk = currentHunk {
            hunks.append(DiffHunk(
                oldStart: hunk.header.oldStart,
                oldCount: hunk.header.oldCount,
                newStart: hunk.header.newStart,
                newCount: hunk.header.newCount,
                context: hunk.header.context,
                lines: hunk.lines
            ))
        }

        return hunks
    }

    /// Parse hunk header: @@ -10,5 +10,7 @@ optional context
    static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, context: String?)? {
        // Pattern: @@ -oldStart,oldCount +newStart,newCount @@ context
        let pattern = #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)?"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        func extractInt(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: line) else { return nil }
            return Int(line[range])
        }

        func extractString(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: line) else { return nil }
            let str = String(line[range]).trimmingCharacters(in: .whitespaces)
            return str.isEmpty ? nil : str
        }

        guard let oldStart = extractInt(1),
              let newStart = extractInt(3) else {
            return nil
        }

        let oldCount = extractInt(2) ?? 1
        let newCount = extractInt(4) ?? 1
        let context = extractString(5)

        return (oldStart, oldCount, newStart, newCount, context)
    }

    /// Detect change type from diff content
    private static func detectChangeType(from lines: [String], linesAdded: Int, linesRemoved: Int) -> FileChangeType {
        // Check for new file mode
        for line in lines {
            if line.contains("new file mode") {
                return .created
            }
            if line.contains("deleted file mode") {
                return .deleted
            }
            if line.contains("rename from") || line.contains("similarity index") {
                return .renamed
            }
        }

        // Check --- /dev/null (new file) or +++ /dev/null (deleted file)
        for line in lines {
            if line.hasPrefix("--- /dev/null") || line.hasPrefix("--- a/dev/null") {
                return .created
            }
            if line.hasPrefix("+++ /dev/null") || line.hasPrefix("+++ b/dev/null") {
                return .deleted
            }
        }

        return .modified
    }

    /// Parse stat counts from stat string (e.g., "10 ++++----" or "5 ++")
    private static func parseStatCounts(_ statsString: String) -> (added: Int, removed: Int) {
        // Check for binary
        if statsString.contains("Bin") {
            return (0, 0)
        }

        // Count + and - characters, or parse the number
        let plusCount = statsString.filter { $0 == "+" }.count
        let minusCount = statsString.filter { $0 == "-" }.count

        // If we have + and - chars, use those
        if plusCount > 0 || minusCount > 0 {
            return (plusCount, minusCount)
        }

        // Otherwise try to parse the leading number as total changes
        let numbers = statsString.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }

        if let total = numbers.first {
            // If only a number, assume all additions (common for new files)
            return (total, 0)
        }

        return (0, 0)
    }
}

// MARK: - Convenience Extensions

extension String {
    /// Parse this string as a unified diff
    func parseDiff() -> [FileDiff] {
        DiffParser.parse(self)
    }
}
