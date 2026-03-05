//
//  ToolInputParser.swift
//  unbound-macos
//
//  Utility for parsing tool input JSON into typed values
//

import Foundation

// MARK: - Tool Input Parser

/// Utility for parsing tool input JSON strings into typed values
struct ToolInputParser {
    let input: String?
    private let parsedDictionary: [String: Any]?

    init(_ input: String?) {
        self.input = input
        if let input,
           let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.parsedDictionary = json
        } else {
            self.parsedDictionary = nil
        }
    }

    /// Parse input as JSON dictionary
    var dictionary: [String: Any]? {
        parsedDictionary
    }

    /// Get string value for key
    func string(_ key: String) -> String? {
        dictionary?[key] as? String
    }

    /// Get integer value for key
    func int(_ key: String) -> Int? {
        dictionary?[key] as? Int
    }

    /// Get boolean value for key
    func bool(_ key: String) -> Bool? {
        dictionary?[key] as? Bool
    }

    /// Get string array value for key
    func stringArray(_ key: String) -> [String]? {
        dictionary?[key] as? [String]
    }

    /// Get nested dictionary for key
    func nested(_ key: String) -> [String: Any]? {
        dictionary?[key] as? [String: Any]
    }

    // MARK: - Common Tool Inputs

    /// File path for Read/Write/Edit tools
    var filePath: String? {
        string("file_path")
    }

    /// Command for Bash tool
    var command: String? {
        string("command")
    }

    /// Description for Bash tool
    var commandDescription: String? {
        string("description")
    }

    /// Pattern for Glob/Grep tools
    var pattern: String? {
        string("pattern")
    }

    /// Path for search tools
    var path: String? {
        string("path")
    }

    /// URL for WebFetch tool
    var url: String? {
        string("url")
    }

    /// Query for WebSearch tool
    var query: String? {
        string("query")
    }

    /// Prompt for WebFetch tool
    var prompt: String? {
        string("prompt")
    }

    /// Content for Write tool
    var content: String? {
        string("content")
    }

    /// Old string for Edit tool
    var oldString: String? {
        string("old_string")
    }

    /// New string for Edit tool
    var newString: String? {
        string("new_string")
    }

    /// Task description for Task tool
    var taskDescription: String? {
        string("description")
    }

    /// Subagent type for Task tool
    var subagentType: String? {
        string("subagent_type")
    }
}

// MARK: - Tool Output Parser

/// Utility for parsing tool output strings
struct ToolOutputParser {
    let output: String?
    private let cachedLineCount: Int
    private let cachedHasVisibleContent: Bool

    init(_ output: String?) {
        self.output = output
        guard let output else {
            self.cachedLineCount = 0
            self.cachedHasVisibleContent = false
            return
        }

        self.cachedLineCount = output.isEmpty ? 0 : output.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
        self.cachedHasVisibleContent = output.unicodeScalars.contains { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }

    /// Output as lines
    var lines: [String] {
        output?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
    }

    /// Output trimmed
    var trimmed: String {
        output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var lineCount: Int {
        cachedLineCount
    }

    var hasVisibleContent: Bool {
        cachedHasVisibleContent
    }

    /// Check if output indicates success (no error markers)
    var isSuccess: Bool {
        guard let output = output else { return true }
        let lowered = output.lowercased()
        return !lowered.contains("error:") && !lowered.contains("fatal:") && !lowered.contains("failed")
    }

    /// Output truncated to max lines
    func truncated(maxLines: Int = 50) -> String {
        guard let output else { return "" }
        guard maxLines > 0 else { return "" }
        if lineCount <= maxLines {
            return output
        }

        var newlineCount = 0
        var cutoffIndex = output.endIndex
        var index = output.startIndex

        while index < output.endIndex {
            if output[index] == "\n" {
                newlineCount += 1
                if newlineCount >= maxLines {
                    cutoffIndex = index
                    break
                }
            }
            index = output.index(after: index)
        }

        let shown = String(output[..<cutoffIndex])
        let remaining = max(0, lineCount - maxLines)
        return "\(shown)\n... (\(remaining) more lines)"
    }
}
