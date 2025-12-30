//
//  ClaudeOutputParser.swift
//  unbound-macos
//
//  Parses Claude CLI streaming output into structured types
//

import Foundation

class ClaudeOutputParser {
    private var buffer: String = ""
    private var inCodeBlock: Bool = false
    private var codeBlockLanguage: String = ""
    private var codeBlockContent: String = ""

    // ANSI escape code pattern
    private let ansiPattern = try! NSRegularExpression(pattern: "\\x1B\\[[0-9;]*[A-Za-z]", options: [])

    /// Reset parser state
    func reset() {
        buffer = ""
        inCodeBlock = false
        codeBlockLanguage = ""
        codeBlockContent = ""
    }

    /// Parse a streaming chunk and return any complete content
    func parse(_ chunk: String) -> [MessageContent] {
        let cleanChunk = stripAnsiCodes(chunk)
        buffer += cleanChunk

        var contents: [MessageContent] = []

        // Process buffer line by line
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])

            if let content = processLine(line) {
                contents.append(content)
            }
        }

        return contents
    }

    /// Finalize parsing and return any remaining content
    func finalize() -> [MessageContent] {
        var contents: [MessageContent] = []

        // Process remaining buffer
        if !buffer.isEmpty {
            if let content = processLine(buffer) {
                contents.append(content)
            }
            buffer = ""
        }

        // Close any open code block
        if inCodeBlock {
            contents.append(.codeBlock(CodeBlock(
                language: codeBlockLanguage,
                code: codeBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )))
            inCodeBlock = false
            codeBlockContent = ""
        }

        return contents
    }

    /// Process a single line
    private func processLine(_ line: String) -> MessageContent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Check for code block markers
        if trimmed.hasPrefix("```") {
            if inCodeBlock {
                // End of code block
                let content = MessageContent.codeBlock(CodeBlock(
                    language: codeBlockLanguage,
                    code: codeBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                inCodeBlock = false
                codeBlockLanguage = ""
                codeBlockContent = ""
                return content
            } else {
                // Start of code block
                inCodeBlock = true
                codeBlockLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeBlockContent = ""
                return nil
            }
        }

        // If in code block, accumulate content
        if inCodeBlock {
            codeBlockContent += line + "\n"
            return nil
        }

        // Check for todo items
        if let todoItem = parseTodoItem(trimmed) {
            return .todoList(TodoList(items: [todoItem]))
        }

        // Check for file change indicators
        if let fileChange = parseFileChange(trimmed) {
            return .fileChange(fileChange)
        }

        // Check for tool use patterns
        if let toolUse = parseToolUse(trimmed) {
            return .toolUse(toolUse)
        }

        // Default to text content if line is not empty
        if !trimmed.isEmpty {
            return .text(TextContent(text: line))
        }

        return nil
    }

    /// Strip ANSI escape codes from text
    func stripAnsiCodes(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return ansiPattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// Parse a todo item from a line
    private func parseTodoItem(_ line: String) -> TodoItem? {
        // Match patterns like:
        // - [ ] Task description
        // - [x] Completed task
        // - [~] In progress task
        // ✓ Completed task
        // • Pending task

        if line.hasPrefix("- [ ]") || line.hasPrefix("- []") {
            let content = String(line.dropFirst(line.hasPrefix("- [ ]") ? 5 : 4)).trimmingCharacters(in: .whitespaces)
            return TodoItem(content: content, status: .pending)
        }

        if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") {
            let content = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return TodoItem(content: content, status: .completed)
        }

        if line.hasPrefix("- [~]") {
            let content = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return TodoItem(content: content, status: .inProgress)
        }

        return nil
    }

    /// Parse file change from a line
    private func parseFileChange(_ line: String) -> FileChange? {
        // Match patterns like:
        // Created: path/to/file.swift
        // Modified: path/to/file.swift
        // Deleted: path/to/file.swift

        let patterns: [(String, FileChangeType)] = [
            ("Created:", .created),
            ("Modified:", .modified),
            ("Deleted:", .deleted),
            ("Renamed:", .renamed),
            ("✓ Created", .created),
            ("✓ Modified", .modified),
            ("✓ Deleted", .deleted)
        ]

        for (prefix, changeType) in patterns {
            if line.hasPrefix(prefix) {
                let path = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return FileChange(filePath: path, changeType: changeType)
            }
        }

        return nil
    }

    /// Parse tool use from a line
    private func parseToolUse(_ line: String) -> ToolUse? {
        // Match patterns like:
        // ⠋ Running: command
        // ✓ Completed: command
        // ✗ Failed: command
        // Using tool: toolname

        let runningPrefixes = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        for prefix in runningPrefixes {
            if line.hasPrefix(prefix) {
                let rest = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return ToolUse(toolName: rest, status: .running)
            }
        }

        if line.hasPrefix("✓") {
            let rest = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            return ToolUse(toolName: rest, status: .completed)
        }

        if line.hasPrefix("✗") {
            let rest = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            return ToolUse(toolName: rest, status: .failed)
        }

        return nil
    }

    /// Detect if line is an interactive prompt
    func detectPrompt(_ text: String) -> AskUserQuestion? {
        // Look for patterns that indicate an interactive prompt
        // This is a simplified detection - real implementation would be more sophisticated

        // Pattern: numbered options like "1. Option one"
        let lines = text.components(separatedBy: "\n")
        var options: [QuestionOption] = []
        var question: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect question (ends with ?)
            if trimmed.hasSuffix("?") && question == nil {
                question = trimmed
            }

            // Detect numbered options
            if let match = trimmed.firstMatch(of: /^(\d+)\.\s+(.+)$/) {
                let label = String(match.2)
                options.append(QuestionOption(label: label))
            }

            // Detect lettered options (case insensitive)
            if let match = trimmed.firstMatch(of: /^([a-zA-Z])\)\s+(.+)$/) {
                let label = String(match.2)
                options.append(QuestionOption(label: label))
            }
        }

        if let q = question, !options.isEmpty {
            return AskUserQuestion(
                question: q,
                options: options,
                allowsMultiSelect: false,
                allowsTextInput: true
            )
        }

        return nil
    }
}
