//
//  SyntaxHighlighter.swift
//  unbound-macos
//
//  Lightweight syntax highlighter for common programming languages
//

import SwiftUI
import AppKit

// MARK: - Token Types

enum SyntaxTokenType {
    case keyword
    case string
    case comment
    case number
    case type
    case function
    case property
    case `operator`
    case punctuation
    case plain
}

// MARK: - Syntax Theme

struct SyntaxTheme {
    let keyword: Color
    let string: Color
    let comment: Color
    let number: Color
    let type: Color
    let function: Color
    let property: Color
    let `operator`: Color
    let punctuation: Color
    let plain: Color
    let background: Color

    static func forColorScheme(_ colorScheme: ColorScheme) -> SyntaxTheme {
        let colors = ThemeColors(colorScheme)
        return SyntaxTheme(
            keyword: colors.accentAmber,
            string: colors.fileUntracked,
            comment: colors.textDimmed,
            number: colors.fileModified,
            type: colors.textMuted,
            function: colors.textSecondary,
            property: colors.textInactive,
            operator: colors.textInactive,
            punctuation: colors.gray8A8,
            plain: colors.textSecondary,
            background: colors.chatBackground
        )
    }

    func color(for tokenType: SyntaxTokenType) -> Color {
        switch tokenType {
        case .keyword: return keyword
        case .string: return string
        case .comment: return comment
        case .number: return number
        case .type: return type
        case .function: return function
        case .property: return property
        case .operator: return `operator`
        case .punctuation: return punctuation
        case .plain: return plain
        }
    }
}

// MARK: - Language Definitions

struct LanguageDefinition {
    let keywords: Set<String>
    let types: Set<String>
    let stringDelimiters: [String]
    let singleLineComment: String?
    let multiLineCommentStart: String?
    let multiLineCommentEnd: String?

    static let swift = LanguageDefinition(
        keywords: ["func", "var", "let", "if", "else", "guard", "return", "for", "while", "switch", "case", "break", "continue", "default", "import", "class", "struct", "enum", "protocol", "extension", "public", "private", "internal", "fileprivate", "open", "static", "final", "override", "mutating", "throws", "throw", "try", "catch", "async", "await", "actor", "init", "deinit", "self", "Self", "super", "nil", "true", "false", "in", "where", "as", "is", "some", "any", "weak", "unowned", "lazy", "defer", "do", "repeat", "typealias", "associatedtype", "inout", "convenience", "required", "optional", "get", "set", "willSet", "didSet", "@State", "@Binding", "@Published", "@Observable", "@ObservedObject", "@EnvironmentObject", "@Environment", "@MainActor", "@escaping", "@autoclosure", "@discardableResult", "@available", "@objc"],
        types: ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "Void", "Any", "AnyObject", "UUID", "Date", "Data", "URL", "View", "Color", "Text", "Image", "Button", "VStack", "HStack", "ZStack", "List", "ForEach", "NavigationView", "NavigationStack", "Task"],
        stringDelimiters: ["\"", "\"\"\""],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/"
    )

    static let javascript = LanguageDefinition(
        keywords: ["const", "let", "var", "function", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "default", "try", "catch", "finally", "throw", "new", "delete", "typeof", "instanceof", "in", "of", "class", "extends", "super", "this", "static", "get", "set", "async", "await", "yield", "import", "export", "from", "as", "default", "true", "false", "null", "undefined", "void", "with", "debugger"],
        types: ["String", "Number", "Boolean", "Object", "Array", "Function", "Symbol", "BigInt", "Map", "Set", "WeakMap", "WeakSet", "Promise", "Date", "RegExp", "Error", "JSON", "Math", "console", "window", "document"],
        stringDelimiters: ["\"", "'", "`"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/"
    )

    static let typescript = LanguageDefinition(
        keywords: javascript.keywords.union(["type", "interface", "enum", "namespace", "module", "declare", "abstract", "implements", "private", "protected", "public", "readonly", "keyof", "infer", "extends", "never", "unknown", "any", "asserts", "is", "satisfies"]),
        types: javascript.types.union(["Partial", "Required", "Readonly", "Record", "Pick", "Omit", "Exclude", "Extract", "NonNullable", "ReturnType", "Parameters", "ConstructorParameters", "InstanceType", "ThisType", "Awaited"]),
        stringDelimiters: ["\"", "'", "`"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/"
    )

    static let python = LanguageDefinition(
        keywords: ["def", "class", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "import", "from", "return", "yield", "raise", "pass", "break", "continue", "and", "or", "not", "in", "is", "lambda", "global", "nonlocal", "assert", "del", "True", "False", "None", "async", "await", "match", "case"],
        types: ["str", "int", "float", "bool", "list", "dict", "set", "tuple", "bytes", "type", "object", "range", "enumerate", "zip", "map", "filter", "print", "len", "open", "self", "cls", "Any", "Optional", "Union", "List", "Dict", "Set", "Tuple", "Callable", "TypeVar", "Generic"],
        stringDelimiters: ["\"", "'", "\"\"\"", "'''"],
        singleLineComment: "#",
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil
    )

    static let rust = LanguageDefinition(
        keywords: ["fn", "let", "mut", "const", "if", "else", "match", "loop", "while", "for", "in", "break", "continue", "return", "struct", "enum", "impl", "trait", "type", "where", "pub", "crate", "mod", "use", "as", "self", "Self", "super", "dyn", "static", "extern", "unsafe", "async", "await", "move", "ref", "true", "false"],
        types: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Rc", "Arc", "Cell", "RefCell", "HashMap", "HashSet", "BTreeMap", "BTreeSet"],
        stringDelimiters: ["\""],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/"
    )

    static let go = LanguageDefinition(
        keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var", "true", "false", "nil", "iota"],
        types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any", "comparable"],
        stringDelimiters: ["\"", "`"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/"
    )

    static let json = LanguageDefinition(
        keywords: ["true", "false", "null"],
        types: [],
        stringDelimiters: ["\""],
        singleLineComment: nil,
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil
    )

    static let bash = LanguageDefinition(
        keywords: ["if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until", "do", "done", "in", "function", "return", "exit", "break", "continue", "export", "local", "readonly", "declare", "typeset", "unset", "shift", "source", "alias", "eval", "exec", "set", "true", "false"],
        types: ["echo", "cd", "ls", "pwd", "mkdir", "rm", "cp", "mv", "cat", "grep", "sed", "awk", "find", "chmod", "chown", "curl", "wget", "git", "npm", "yarn", "node", "python", "pip", "docker", "kubectl"],
        stringDelimiters: ["\"", "'"],
        singleLineComment: "#",
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil
    )

    static let sql = LanguageDefinition(
        keywords: ["SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "FULL", "CROSS", "ON", "AS", "ORDER", "BY", "ASC", "DESC", "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "INDEX", "VIEW", "DROP", "ALTER", "ADD", "COLUMN", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "UNIQUE", "CHECK", "CASCADE", "RESTRICT", "RETURNING", "WITH", "RECURSIVE", "CASE", "WHEN", "THEN", "ELSE", "END", "COALESCE", "NULLIF", "CAST", "TRUE", "FALSE", "select", "from", "where", "and", "or", "not", "in", "is", "null", "like", "between", "exists", "join", "inner", "left", "right", "outer", "full", "cross", "on", "as", "order", "by", "asc", "desc", "group", "having", "limit", "offset", "union", "all", "distinct", "insert", "into", "values", "update", "set", "delete", "create", "table", "index", "view", "drop", "alter", "add", "column", "primary", "key", "foreign", "references", "constraint", "default", "unique", "check", "cascade", "restrict", "returning", "with", "recursive", "case", "when", "then", "else", "end", "coalesce", "nullif", "cast", "true", "false"],
        types: ["INT", "INTEGER", "BIGINT", "SMALLINT", "SERIAL", "BIGSERIAL", "DECIMAL", "NUMERIC", "REAL", "DOUBLE", "PRECISION", "FLOAT", "BOOLEAN", "BOOL", "CHAR", "VARCHAR", "TEXT", "DATE", "TIME", "TIMESTAMP", "TIMESTAMPTZ", "INTERVAL", "UUID", "JSON", "JSONB", "ARRAY", "BYTEA", "int", "integer", "bigint", "smallint", "serial", "bigserial", "decimal", "numeric", "real", "double", "precision", "float", "boolean", "bool", "char", "varchar", "text", "date", "time", "timestamp", "timestamptz", "interval", "uuid", "json", "jsonb", "array", "bytea"],
        stringDelimiters: ["'"],
        singleLineComment: "--",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/"
    )

    static func forLanguage(_ language: String?) -> LanguageDefinition? {
        guard let lang = language?.lowercased() else { return nil }
        switch lang {
        case "swift": return .swift
        case "javascript", "js", "jsx": return .javascript
        case "typescript", "ts", "tsx": return .typescript
        case "python", "py": return .python
        case "rust", "rs": return .rust
        case "go", "golang": return .go
        case "json": return .json
        case "bash", "sh", "shell", "zsh": return .bash
        case "sql", "postgresql", "postgres", "mysql", "sqlite": return .sql
        default: return nil
        }
    }
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {
    let theme: SyntaxTheme
    let language: LanguageDefinition?

    init(language: String?, colorScheme: ColorScheme) {
        self.theme = SyntaxTheme.forColorScheme(colorScheme)
        self.language = LanguageDefinition.forLanguage(language)
    }

    func highlight(_ code: String) -> AttributedString {
        guard let language = language else {
            var result = AttributedString(code)
            result.foregroundColor = theme.plain
            return result
        }

        var result = AttributedString()
        var index = code.startIndex
        let endIndex = code.endIndex

        while index < endIndex {
            // Check for multi-line comments
            if let mlStart = language.multiLineCommentStart,
               let mlEnd = language.multiLineCommentEnd,
               code[index...].hasPrefix(mlStart) {
                let (token, newIndex) = extractMultiLineComment(from: code, startingAt: index, start: mlStart, end: mlEnd)
                result.append(styledToken(token, type: .comment))
                index = newIndex
                continue
            }

            // Check for single-line comments
            if let slComment = language.singleLineComment,
               code[index...].hasPrefix(slComment) {
                let (token, newIndex) = extractLineComment(from: code, startingAt: index)
                result.append(styledToken(token, type: .comment))
                index = newIndex
                continue
            }

            // Check for strings
            for delimiter in language.stringDelimiters {
                if code[index...].hasPrefix(delimiter) {
                    let (token, newIndex) = extractString(from: code, startingAt: index, delimiter: delimiter)
                    result.append(styledToken(token, type: .string))
                    index = newIndex
                    break
                }
            }
            if index >= endIndex { break }

            // Check for numbers
            let char = code[index]
            if char.isNumber || (char == "." && index < code.index(before: endIndex) && code[code.index(after: index)].isNumber) {
                let (token, newIndex) = extractNumber(from: code, startingAt: index)
                result.append(styledToken(token, type: .number))
                index = newIndex
                continue
            }

            // Check for identifiers (keywords, types, etc.)
            if char.isLetter || char == "_" || char == "@" || char == "$" {
                let (token, newIndex) = extractIdentifier(from: code, startingAt: index)
                let tokenType = classifyIdentifier(token, language: language)
                result.append(styledToken(token, type: tokenType))
                index = newIndex
                continue
            }

            // Check for operators
            if isOperatorChar(char) {
                let (token, newIndex) = extractOperator(from: code, startingAt: index)
                result.append(styledToken(token, type: .operator))
                index = newIndex
                continue
            }

            // Check for punctuation
            if isPunctuationChar(char) {
                result.append(styledToken(String(char), type: .punctuation))
                index = code.index(after: index)
                continue
            }

            // Plain character (whitespace, etc.)
            result.append(styledToken(String(char), type: .plain))
            index = code.index(after: index)
        }

        return result
    }

    // MARK: - Token Extraction

    private func extractMultiLineComment(from code: String, startingAt start: String.Index, start mlStart: String, end mlEnd: String) -> (String, String.Index) {
        var index = code.index(start, offsetBy: mlStart.count)
        while index < code.endIndex {
            if code[index...].hasPrefix(mlEnd) {
                let endIdx = code.index(index, offsetBy: mlEnd.count)
                return (String(code[start..<endIdx]), endIdx)
            }
            index = code.index(after: index)
        }
        return (String(code[start...]), code.endIndex)
    }

    private func extractLineComment(from code: String, startingAt start: String.Index) -> (String, String.Index) {
        var index = start
        while index < code.endIndex && code[index] != "\n" {
            index = code.index(after: index)
        }
        return (String(code[start..<index]), index)
    }

    private func extractString(from code: String, startingAt start: String.Index, delimiter: String) -> (String, String.Index) {
        let isTripleQuote = delimiter.count == 3
        var index = code.index(start, offsetBy: delimiter.count)
        var escaped = false

        while index < code.endIndex {
            let char = code[index]

            if escaped {
                escaped = false
                index = code.index(after: index)
                continue
            }

            if char == "\\" && !isTripleQuote {
                escaped = true
                index = code.index(after: index)
                continue
            }

            if code[index...].hasPrefix(delimiter) {
                let endIdx = code.index(index, offsetBy: delimiter.count)
                return (String(code[start..<endIdx]), endIdx)
            }

            index = code.index(after: index)
        }

        return (String(code[start...]), code.endIndex)
    }

    private func extractNumber(from code: String, startingAt start: String.Index) -> (String, String.Index) {
        var index = start
        var hasDecimal = false
        var hasExponent = false

        // Handle hex (0x), binary (0b), octal (0o)
        if code[index] == "0" && code.index(after: index) < code.endIndex {
            let next = code[code.index(after: index)]
            if next == "x" || next == "X" || next == "b" || next == "B" || next == "o" || next == "O" {
                index = code.index(index, offsetBy: 2)
                while index < code.endIndex && (code[index].isHexDigit || code[index] == "_") {
                    index = code.index(after: index)
                }
                return (String(code[start..<index]), index)
            }
        }

        while index < code.endIndex {
            let char = code[index]
            if char.isNumber || char == "_" {
                index = code.index(after: index)
            } else if char == "." && !hasDecimal && !hasExponent {
                hasDecimal = true
                index = code.index(after: index)
            } else if (char == "e" || char == "E") && !hasExponent {
                hasExponent = true
                index = code.index(after: index)
                if index < code.endIndex && (code[index] == "+" || code[index] == "-") {
                    index = code.index(after: index)
                }
            } else {
                break
            }
        }

        return (String(code[start..<index]), index)
    }

    private func extractIdentifier(from code: String, startingAt start: String.Index) -> (String, String.Index) {
        var index = start
        while index < code.endIndex {
            let char = code[index]
            if char.isLetter || char.isNumber || char == "_" || char == "@" || char == "$" {
                index = code.index(after: index)
            } else {
                break
            }
        }
        return (String(code[start..<index]), index)
    }

    private func extractOperator(from code: String, startingAt start: String.Index) -> (String, String.Index) {
        var index = start
        while index < code.endIndex && isOperatorChar(code[index]) {
            index = code.index(after: index)
        }
        return (String(code[start..<index]), index)
    }

    // MARK: - Classification

    private func classifyIdentifier(_ token: String, language: LanguageDefinition) -> SyntaxTokenType {
        if language.keywords.contains(token) {
            return .keyword
        }
        if language.types.contains(token) {
            return .type
        }
        // Check if it looks like a type (starts with uppercase)
        if let first = token.first, first.isUppercase {
            return .type
        }
        return .plain
    }

    private func isOperatorChar(_ char: Character) -> Bool {
        let operators: Set<Character> = ["+", "-", "*", "/", "%", "=", "<", ">", "!", "&", "|", "^", "~", "?", ":"]
        return operators.contains(char)
    }

    private func isPunctuationChar(_ char: Character) -> Bool {
        let punctuation: Set<Character> = ["(", ")", "[", "]", "{", "}", ",", ";", ".", "`"]
        return punctuation.contains(char)
    }

    // MARK: - Styling

    private func styledToken(_ token: String, type: SyntaxTokenType) -> AttributedString {
        var attr = AttributedString(token)
        attr.foregroundColor = theme.color(for: type)
        return attr
    }
}

// MARK: - SwiftUI View Extension

struct HighlightedCodeText: View {
    @Environment(\.colorScheme) private var colorScheme

    let code: String
    let language: String?

    @State private var highlightedText: AttributedString?

    var body: some View {
        Group {
            if let highlightedText {
                Text(highlightedText)
            } else {
                // Show plain text while highlighting in background
                Text(code)
                    .foregroundColor(ThemeColors(colorScheme).textMuted)
            }
        }
        .font(Typography.code)
        .textSelection(.enabled)
        .task(id: HighlightTaskId(code: code, language: language, colorScheme: colorScheme)) {
            let codeCopy = code
            let languageCopy = language
            let schemeCopy = colorScheme

            let result = await Task.detached(priority: .userInitiated) {
                let highlighter = SyntaxHighlighter(language: languageCopy, colorScheme: schemeCopy)
                return highlighter.highlight(codeCopy)
            }.value

            highlightedText = result
        }
    }
}

/// Hashable identifier for the highlight task to re-run when inputs change
private struct HighlightTaskId: Hashable {
    let code: String
    let language: String?
    let colorScheme: ColorScheme
}

// MARK: - Language Helper

extension SyntaxHighlighter {
    static func languageIdentifier(forFilePath path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "json": return "json"
        case "yml", "yaml": return "yaml"
        case "sh", "zsh", "bash": return "bash"
        case "sql": return "sql"
        default: return nil
        }
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HighlightedCodeText(
                code: """
                func greet(name: String) -> String {
                    // Return a greeting message
                    let message = "Hello, \\(name)!"
                    return message
                }

                let result = greet(name: "World")
                print(result) // prints: Hello, World!
                """,
                language: "swift"
            )

            HighlightedCodeText(
                code: """
                const fetchData = async (url) => {
                    // Fetch data from API
                    const response = await fetch(url);
                    const data = await response.json();
                    return data;
                };

                fetchData('https://api.example.com')
                    .then(data => console.log(data));
                """,
                language: "javascript"
            )

            HighlightedCodeText(
                code: """
                SELECT u.name, COUNT(o.id) as order_count
                FROM users u
                LEFT JOIN orders o ON u.id = o.user_id
                WHERE u.created_at > '2024-01-01'
                GROUP BY u.id
                HAVING COUNT(o.id) > 5
                ORDER BY order_count DESC;
                """,
                language: "sql"
            )
        }
        .padding()
    }
    .frame(width: 600, height: 500)
}
