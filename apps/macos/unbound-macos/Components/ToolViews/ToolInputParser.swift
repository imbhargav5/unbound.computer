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

    init(_ input: String?) {
        self.input = input
    }

    /// Parse input as JSON dictionary
    var dictionary: [String: Any]? {
        guard let input = input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
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

    init(_ output: String?) {
        self.output = output
    }

    /// Output as lines
    var lines: [String] {
        output?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
    }

    /// Output trimmed
    var trimmed: String {
        output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Check if output indicates success (no error markers)
    var isSuccess: Bool {
        guard let output = output else { return true }
        let lowered = output.lowercased()
        return !lowered.contains("error:") && !lowered.contains("fatal:") && !lowered.contains("failed")
    }

    /// Output truncated to max lines
    func truncated(maxLines: Int = 50) -> String {
        let allLines = lines
        if allLines.count <= maxLines {
            return output ?? ""
        }
        let shown = allLines.prefix(maxLines).joined(separator: "\n")
        let remaining = allLines.count - maxLines
        return "\(shown)\n... (\(remaining) more lines)"
    }
}
