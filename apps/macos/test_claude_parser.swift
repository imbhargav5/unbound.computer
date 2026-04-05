#!/usr/bin/env swift
import Foundation

// MARK: - Message Content Types

enum MessageContent: Equatable {
    case text(TextContent)
    case codeBlock(CodeBlock)
    case todoList(TodoList)
    case fileChange(FileChange)
    case toolUse(ToolUse)
}

struct TextContent: Equatable {
    let text: String
}

struct CodeBlock: Equatable {
    let language: String
    let code: String
}

enum TodoStatus: String, Equatable {
    case pending
    case completed
    case inProgress
}

struct TodoItem: Equatable {
    let content: String
    let status: TodoStatus
}

struct TodoList: Equatable {
    let items: [TodoItem]
}

enum FileChangeType: Equatable {
    case created
    case modified
    case deleted
    case renamed
}

struct FileChange: Equatable {
    let filePath: String
    let changeType: FileChangeType
}

enum ToolStatus: Equatable {
    case running
    case completed
    case failed
}

struct ToolUse: Equatable {
    let toolName: String
    let status: ToolStatus
}

// MARK: - ClaudeOutputParser Implementation

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
}

// MARK: - Test Runner

print("🧪 Testing ClaudeOutputParser")
print("==============================\n")

// Test 1: Parse simple code block
print("Test 1: Parse Simple Code Block")
print("-------------------------------")
let parser1 = ClaudeOutputParser()
let input1 = """
```swift
let x = 5
let y = 10
```
"""
let parsed1 = parser1.parse(input1 + "\n")
let finalized1 = parser1.finalize()
let result1 = parsed1 + finalized1
assert(result1.count >= 1, "Should parse at least one code block")
if case .codeBlock(let block) = result1[0] {
    assert(block.language == "swift", "Language should be swift")
    assert(block.code.contains("let x = 5"), "Code should contain content")
    print("  ✓ Language: \(block.language)")
    print("  ✓ Code lines: \(block.code.split(separator: "\n").count)")
} else {
    fatalError("Expected code block, got \(result1[0])")
}
print("  ✅ PASSED\n")

// Test 2: Parse code block without language
print("Test 2: Parse Code Block Without Language")
print("-----------------------------------------")
let parser2 = ClaudeOutputParser()
let input2 = """
```
console.log('hello')
```
"""
let parsed2 = parser2.parse(input2 + "\n")
let finalized2 = parser2.finalize()
let result2 = parsed2 + finalized2
assert(result2.count >= 1, "Should parse at least one code block")
if case .codeBlock(let block) = result2[0] {
    assert(block.language == "", "Language should be empty")
    assert(block.code.contains("console.log"), "Code should contain content")
    print("  ✓ Empty language detected")
} else {
    fatalError("Expected code block")
}
print("  ✅ PASSED\n")

// Test 3: Parse pending todo items
print("Test 3: Parse Pending Todo Items")
print("--------------------------------")
let parser3 = ClaudeOutputParser()
let input3 = """
- [ ] Task one
- [ ] Task two
"""
let result3 = parser3.parse(input3 + "\n")
assert(result3.count == 2, "Should parse two todo items")
if case .todoList(let list1) = result3[0],
   case .todoList(let list2) = result3[1] {
    assert(list1.items[0].status == .pending, "First todo should be pending")
    assert(list2.items[0].status == .pending, "Second todo should be pending")
    assert(list1.items[0].content == "Task one", "Content should match")
    print("  ✓ Parsed \(result3.count) pending todos")
} else {
    fatalError("Expected todo lists")
}
print("  ✅ PASSED\n")

// Test 4: Parse completed todo items
print("Test 4: Parse Completed Todo Items")
print("----------------------------------")
let parser4 = ClaudeOutputParser()
let input4 = """
- [x] Done task
- [X] Also done
"""
let result4 = parser4.parse(input4 + "\n")
assert(result4.count == 2, "Should parse two completed todos")
if case .todoList(let list1) = result4[0],
   case .todoList(let list2) = result4[1] {
    assert(list1.items[0].status == .completed, "Should be completed")
    assert(list2.items[0].status == .completed, "Should be completed (uppercase X)")
    print("  ✓ Parsed \(result4.count) completed todos")
} else {
    fatalError("Expected todo lists")
}
print("  ✅ PASSED\n")

// Test 5: Parse in-progress todo items
print("Test 5: Parse In-Progress Todo Items")
print("------------------------------------")
let parser5 = ClaudeOutputParser()
let input5 = "- [~] Working on it\n"
let result5 = parser5.parse(input5)
assert(result5.count == 1, "Should parse one in-progress todo")
if case .todoList(let list) = result5[0] {
    assert(list.items[0].status == .inProgress, "Should be in-progress")
    assert(list.items[0].content == "Working on it", "Content should match")
    print("  ✓ Parsed in-progress todo")
} else {
    fatalError("Expected todo list")
}
print("  ✅ PASSED\n")

// Test 6: Parse file changes
print("Test 6: Parse File Changes")
print("--------------------------")
let parser6 = ClaudeOutputParser()
let input6 = """
Created: src/main.swift
Modified: src/utils.swift
Deleted: src/old.swift
"""
let result6 = parser6.parse(input6 + "\n")
assert(result6.count == 3, "Should parse three file changes")
if case .fileChange(let change1) = result6[0],
   case .fileChange(let change2) = result6[1],
   case .fileChange(let change3) = result6[2] {
    assert(change1.changeType == .created, "First should be created")
    assert(change2.changeType == .modified, "Second should be modified")
    assert(change3.changeType == .deleted, "Third should be deleted")
    assert(change1.filePath == "src/main.swift", "Path should match")
    print("  ✓ Parsed 3 file changes (created, modified, deleted)")
} else {
    fatalError("Expected file changes")
}
print("  ✅ PASSED\n")

// Test 7: Parse tool use with spinner
print("Test 7: Parse Tool Use With Spinner")
print("-----------------------------------")
let parser7 = ClaudeOutputParser()
let input7 = "⠋ Running: git status\n"
let result7 = parser7.parse(input7)
assert(result7.count == 1, "Should parse one tool use")
if case .toolUse(let tool) = result7[0] {
    assert(tool.status == .running, "Tool should be running")
    assert(tool.toolName == "Running: git status", "Tool name should match")
    print("  ✓ Parsed running tool")
} else {
    fatalError("Expected tool use")
}
print("  ✅ PASSED\n")

// Test 8: Parse tool use completed
print("Test 8: Parse Tool Use Completed")
print("--------------------------------")
let parser8 = ClaudeOutputParser()
let input8 = "✓ Completed: test command\n"
let result8 = parser8.parse(input8)
assert(result8.count == 1, "Should parse one tool use")
if case .toolUse(let tool) = result8[0] {
    assert(tool.status == .completed, "Tool should be completed")
    print("  ✓ Parsed completed tool")
} else {
    fatalError("Expected tool use")
}
print("  ✅ PASSED\n")

// Test 9: Parse tool use failed
print("Test 9: Parse Tool Use Failed")
print("-----------------------------")
let parser9 = ClaudeOutputParser()
let input9 = "✗ Failed: bad command\n"
let result9 = parser9.parse(input9)
assert(result9.count == 1, "Should parse one tool use")
if case .toolUse(let tool) = result9[0] {
    assert(tool.status == .failed, "Tool should be failed")
    print("  ✓ Parsed failed tool")
} else {
    fatalError("Expected tool use")
}
print("  ✅ PASSED\n")

// Test 10: Strip ANSI codes
print("Test 10: Strip ANSI Codes")
print("-------------------------")
let parser10 = ClaudeOutputParser()
let input10 = "\u{1B}[32mGreen text\u{1B}[0m\n"
let result10 = parser10.parse(input10)
assert(result10.count == 1, "Should parse one text item")
if case .text(let text) = result10[0] {
    assert(!text.text.contains("\u{1B}"), "Should not contain ANSI codes")
    assert(text.text.contains("Green text"), "Should contain actual text")
    print("  ✓ ANSI codes stripped")
} else {
    fatalError("Expected text")
}
print("  ✅ PASSED\n")

// Test 11: Handle incomplete buffer (partial lines)
print("Test 11: Handle Incomplete Buffer")
print("---------------------------------")
let parser11 = ClaudeOutputParser()
let chunk1 = "This is partial"
let chunk2 = " line complete\n"
let result11a = parser11.parse(chunk1)
assert(result11a.count == 0, "Partial line should not be parsed yet")
let result11b = parser11.parse(chunk2)
assert(result11b.count == 1, "Complete line should be parsed")
print("  ✓ Handled partial line correctly")
print("  ✅ PASSED\n")

// Test 12: Finalize with open code block
print("Test 12: Finalize With Open Code Block")
print("--------------------------------------")
let parser12 = ClaudeOutputParser()
let input12 = """
```python
def hello():
    print("world")
"""
let _ = parser12.parse(input12 + "\n")
let result12 = parser12.finalize()
assert(result12.count == 1, "Should finalize open code block")
if case .codeBlock(let block) = result12[0] {
    assert(block.language == "python", "Language should be python")
    assert(block.code.contains("def hello"), "Code should be present")
    print("  ✓ Open code block finalized")
} else {
    fatalError("Expected code block")
}
print("  ✅ PASSED\n")

// Test 13: Reset parser state
print("Test 13: Reset Parser State")
print("---------------------------")
let parser13 = ClaudeOutputParser()
let _ = parser13.parse("```swift\ncode\n")
parser13.reset()
let input13 = "- [ ] New task\n"
let result13 = parser13.parse(input13)
assert(result13.count == 1, "Parser should work after reset")
if case .todoList(let list) = result13[0] {
    assert(list.items[0].content == "New task", "Should parse new content")
    print("  ✓ Parser reset successfully")
} else {
    fatalError("Expected todo list")
}
print("  ✅ PASSED\n")

// Test 14: Handle empty chunks
print("Test 14: Handle Empty Chunks")
print("----------------------------")
let parser14 = ClaudeOutputParser()
let result14a = parser14.parse("")
assert(result14a.count == 0, "Empty chunk should return nothing")
let result14b = parser14.parse("\n\n\n")
assert(result14b.count == 0, "Whitespace chunks should return nothing")
print("  ✓ Empty chunks handled correctly")
print("  ✅ PASSED\n")

// Test 15: Handle multiple content types in sequence
print("Test 15: Handle Multiple Content Types")
print("--------------------------------------")
let parser15 = ClaudeOutputParser()
let input15 = """
Some text
- [ ] A task
Created: file.txt
```js
code here
```
More text
"""
let result15 = parser15.parse(input15 + "\n")
assert(result15.count >= 5, "Should parse multiple content types")
print("  ✓ Parsed \(result15.count) items of mixed types")
print("  ✅ PASSED\n")

// Summary
print("==============================")
print("🎉 ALL TESTS PASSED!")
print("==============================")
print("\n✅ ClaudeOutputParser is working correctly!\n")
print("Test Summary:")
print("  ✓ Code block parsing (with/without language)")
print("  ✓ Todo item parsing (pending, completed, in-progress)")
print("  ✓ File change parsing (created, modified, deleted)")
print("  ✓ Tool use parsing (running, completed, failed)")
print("  ✓ ANSI code stripping")
print("  ✓ Buffer management (partial lines, finalization)")
print("  ✓ Parser reset")
print("  ✓ Empty chunks and edge cases")
print("  ✓ Mixed content types")
print("\nReady for production! 🚀")
