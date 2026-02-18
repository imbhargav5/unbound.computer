//
//  MarkdownTextView.swift
//  unbound-macos
//
//  Full markdown text renderer supporting headings, lists, bold, italic, and code
//

import SwiftUI
import AppKit

// MARK: - Markdown Block Types

private enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [ListItem])
    case numberedList(items: [ListItem])
    case codeBlock(language: String?, code: String)
    case horizontalRule
    case blockquote(text: String)

    var id: String {
        switch self {
        case .heading(let level, let text):
            return "h\(level)-\(text.hashValue)"
        case .paragraph(let text):
            return "p-\(text.hashValue)"
        case .bulletList(let items):
            return "ul-\(items.map { $0.text }.joined().hashValue)"
        case .numberedList(let items):
            return "ol-\(items.map { $0.text }.joined().hashValue)"
        case .codeBlock(let lang, let code):
            return "code-\(lang ?? "")-\(code.hashValue)"
        case .horizontalRule:
            return "hr-\(UUID().uuidString)"
        case .blockquote(let text):
            return "bq-\(text.hashValue)"
        }
    }
}

private struct ListItem: Identifiable {
    let id = UUID()
    let text: String
    let indent: Int
}

// MARK: - Markdown Parser

private enum MarkdownBlockParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var currentParagraph: [String] = []
        var currentListItems: [ListItem] = []
        var currentListType: ListType?
        var inCodeBlock = false
        var codeBlockLanguage: String?
        var codeBlockLines: [String] = []

        enum ListType { case bullet, numbered }

        func flushParagraph() {
            if !currentParagraph.isEmpty {
                let text = currentParagraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    blocks.append(.paragraph(text: text))
                }
                currentParagraph = []
            }
        }

        func flushList() {
            if !currentListItems.isEmpty {
                switch currentListType {
                case .bullet:
                    blocks.append(.bulletList(items: currentListItems))
                case .numbered:
                    blocks.append(.numberedList(items: currentListItems))
                case .none:
                    break
                }
                currentListItems = []
                currentListType = nil
            }
        }

        for line in lines {
            // Handle code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(language: codeBlockLanguage, code: codeBlockLines.joined(separator: "\n")))
                    codeBlockLines = []
                    codeBlockLanguage = nil
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    flushList()
                    let langPart = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeBlockLanguage = langPart.isEmpty ? nil : langPart
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeBlockLines.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line - flush current content
            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            // Heading detection
            if let headingMatch = parseHeading(trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: headingMatch.level, text: headingMatch.text))
                continue
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.horizontalRule)
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                let quoteText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.blockquote(text: quoteText))
                continue
            }

            // Bullet list
            if let bulletItem = parseBulletListItem(line) {
                flushParagraph()
                if currentListType != .bullet {
                    flushList()
                    currentListType = .bullet
                }
                currentListItems.append(bulletItem)
                continue
            }

            // Numbered list
            if let numberedItem = parseNumberedListItem(line) {
                flushParagraph()
                if currentListType != .numbered {
                    flushList()
                    currentListType = .numbered
                }
                currentListItems.append(numberedItem)
                continue
            }

            // Regular text - add to paragraph
            currentParagraph.append(line)
        }

        // Flush remaining content
        if inCodeBlock {
            blocks.append(.codeBlock(language: codeBlockLanguage, code: codeBlockLines.joined(separator: "\n")))
        }
        flushParagraph()
        flushList()

        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex

        while index < line.endIndex && line[index] == "#" && level < 6 {
            level += 1
            index = line.index(after: index)
        }

        guard level > 0 && index < line.endIndex && line[index] == " " else {
            return nil
        }

        let text = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.replacingOccurrences(of: " ", with: "")
        return (trimmed.allSatisfy { $0 == "-" } && trimmed.count >= 3) ||
               (trimmed.allSatisfy { $0 == "*" } && trimmed.count >= 3) ||
               (trimmed.allSatisfy { $0 == "_" } && trimmed.count >= 3)
    }

    private static func parseBulletListItem(_ line: String) -> ListItem? {
        // Count leading spaces for indent
        var indent = 0
        var index = line.startIndex
        while index < line.endIndex && (line[index] == " " || line[index] == "\t") {
            indent += line[index] == "\t" ? 2 : 1
            index = line.index(after: index)
        }
        indent = indent / 2

        let remaining = String(line[index...])

        // Check for bullet markers: -, *, +
        guard remaining.count >= 2 else { return nil }
        let firstChar = remaining.first
        guard firstChar == "-" || firstChar == "*" || firstChar == "+" else { return nil }

        let afterMarker = remaining.index(remaining.startIndex, offsetBy: 1)
        guard remaining[afterMarker] == " " else { return nil }

        let text = String(remaining[remaining.index(afterMarker, offsetBy: 1)...]).trimmingCharacters(in: .whitespaces)
        return ListItem(text: text, indent: indent)
    }

    private static func parseNumberedListItem(_ line: String) -> ListItem? {
        // Count leading spaces for indent
        var indent = 0
        var index = line.startIndex
        while index < line.endIndex && (line[index] == " " || line[index] == "\t") {
            indent += line[index] == "\t" ? 2 : 1
            index = line.index(after: index)
        }
        indent = indent / 2

        let remaining = String(line[index...])

        // Match pattern: number followed by . or ) and space
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)[.\)]\s+(.+)$"#),
              let match = regex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
              let textRange = Range(match.range(at: 2), in: remaining) else {
            return nil
        }

        let text = String(remaining[textRange]).trimmingCharacters(in: .whitespaces)
        return ListItem(text: text, indent: indent)
    }
}

// MARK: - Inline Text Renderer

private struct InlineMarkdownText: View {
    let text: String
    let colors: ThemeColors
    let baseFont: Font

    init(_ text: String, colors: ThemeColors, baseFont: Font? = nil) {
        self.text = text
        self.colors = colors
        self.baseFont = baseFont ?? Typography.body
    }

    var body: some View {
        Text(parse())
            .font(baseFont)
            .textSelection(.enabled)
            .lineSpacing(Spacing.xs)
    }

    private func parse() -> AttributedString {
        var result = AttributedString()

        let patterns: [(pattern: String, transform: (String) -> AttributedString)] = [
            // Bold + Code: **`text`**
            (#"\*\*`([^`]+)`\*\*"#, { match in
                var attr = AttributedString(match)
                attr.font = Typography.code.weight(.semibold)
                attr.backgroundColor = colors.muted
                attr.foregroundColor = colors.foreground
                return attr
            }),
            // Code (backticks) - use foreground color for readability
            (#"`([^`]+)`"#, { match in
                var attr = AttributedString(match)
                attr.font = Typography.code
                attr.backgroundColor = colors.muted
                attr.foregroundColor = colors.foreground
                return attr
            }),
            // Bold (double asterisks)
            (#"\*\*([^*]+)\*\*"#, { match in
                var attr = AttributedString(match)
                attr.font = baseFont.weight(.semibold)
                return attr
            }),
            // Bold (double underscores)
            (#"__([^_]+)__"#, { match in
                var attr = AttributedString(match)
                attr.font = baseFont.weight(.semibold)
                return attr
            }),
            // Italic (single asterisk)
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, { match in
                var attr = AttributedString(match)
                attr.font = baseFont.italic()
                return attr
            }),
            // Italic (single underscore)
            (#"(?<!_)_([^_]+)_(?!_)"#, { match in
                var attr = AttributedString(match)
                attr.font = baseFont.italic()
                return attr
            })
        ]

        var processedRanges: [(Range<String.Index>, AttributedString)] = []

        for (pattern, transform) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let captureRange = Range(match.range(at: 1), in: text) else { continue }

                let capturedText = String(text[captureRange])
                let formatted = transform(capturedText)

                processedRanges.append((fullRange, formatted))
            }
        }

        processedRanges.sort { $0.0.lowerBound < $1.0.lowerBound }

        var filteredRanges: [(Range<String.Index>, AttributedString)] = []
        var lastEnd: String.Index = text.startIndex
        for (range, attr) in processedRanges {
            if range.lowerBound >= lastEnd {
                filteredRanges.append((range, attr))
                lastEnd = range.upperBound
            }
        }

        var currentIndex = text.startIndex
        for (range, formatted) in filteredRanges {
            if currentIndex < range.lowerBound {
                let plainText = String(text[currentIndex..<range.lowerBound])
                result.append(AttributedString(plainText))
            }
            result.append(formatted)
            currentIndex = range.upperBound
        }

        if currentIndex < text.endIndex {
            let plainText = String(text[currentIndex...])
            result.append(AttributedString(plainText))
        }

        return result
    }
}

// MARK: - Markdown Code Block View (with copy button)

private struct MarkdownCodeBlockView: View {
    let language: String?
    let code: String
    let colors: ThemeColors

    @State private var isCopied = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }

                Spacer()

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: IconSize.sm))
                        Text(isCopied ? "Copied!" : "Copy")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(isCopied ? colors.success : colors.mutedForeground)
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isCopied ? 1 : 0.6)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(colors.muted)

            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                HighlightedCodeText(code: code, language: language)
                    .padding(Spacing.md)
            }
            .background(colors.card)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let text):
            InlineMarkdownText(text, colors: colors, baseFont: Typography.body)
                .foregroundStyle(colors.textMuted)

        case .bulletList(let items):
            bulletListView(items: items)

        case .numberedList(let items):
            numberedListView(items: items)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)

        case .horizontalRule:
            Divider()
                .padding(.vertical, Spacing.sm)

        case .blockquote(let text):
            blockquoteView(text: text)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: Typography.h1
        case 2: Typography.h2
        case 3: Typography.h3
        case 4: Typography.h4
        default: Typography.label
        }

        InlineMarkdownText(text, colors: colors, baseFont: font)
            .foregroundStyle(colors.foreground)
            .padding(.top, level <= 2 ? Spacing.lg : Spacing.md)
            .padding(.bottom, Spacing.xs)
    }

    @ViewBuilder
    private func bulletListView(items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text("•")
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)
                        .padding(.leading, CGFloat(item.indent) * Spacing.md)

                    InlineMarkdownText(item.text, colors: colors, baseFont: Typography.body)
                        .foregroundStyle(colors.textMuted)
                }
            }
        }
    }

    @ViewBuilder
    private func numberedListView(items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text("\(index + 1).")
                        .font(Typography.body)
                        .foregroundStyle(colors.mutedForeground)
                        .frame(minWidth: 20, alignment: .trailing)
                        .padding(.leading, CGFloat(item.indent) * Spacing.md)

                    InlineMarkdownText(item.text, colors: colors, baseFont: Typography.body)
                        .foregroundStyle(colors.textMuted)
                }
            }
        }
    }

    @ViewBuilder
    private func codeBlockView(language: String?, code: String) -> some View {
        MarkdownCodeBlockView(language: language, code: code, colors: colors)
    }

    @ViewBuilder
    private func blockquoteView(text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(colors.border)
                .frame(width: 3)

            InlineMarkdownText(text, colors: colors)
                .foregroundStyle(colors.mutedForeground)
                .italic()
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarkdownTextView(text: """
        ### **5. Events & Interactions**
        - **`useSwipe`** - Detect swipe gestures (direction, velocity, distance)
        - **`usePinchZoom`** - Handle pinch-to-zoom gestures
        - **`useDoubleTap`** - Detect double tap/click with configurable delay

        ### **6. Network & Data**
        - **`useAbortController`** - Manage AbortController for cancellable fetch requests
        - **`useSSE`** - Server-Sent Events subscription management
        - **`useWebSocket`** - WebSocket connection with auto-reconnect

        This is a regular paragraph with **bold text**, *italic text*, and `inline code`.

        > This is a blockquote

        1. First numbered item
        2. Second numbered item
        3. Third numbered item
        """)
        .padding()
    }
    .frame(width: 600, height: 500)
}
