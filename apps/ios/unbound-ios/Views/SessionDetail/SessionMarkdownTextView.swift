//
//  SessionMarkdownTextView.swift
//  unbound-ios
//
//  iOS markdown renderer for session detail messages.
//  Adapted from macOS MarkdownTextView using iOS AppTheme tokens.
//

import SwiftUI

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
            return "ul-\(items.map(\.text).joined().hashValue)"
        case .numberedList(let items):
            return "ol-\(items.map(\.text).joined().hashValue)"
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
                let text = currentParagraph.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
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
            if line.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(
                        language: codeBlockLanguage,
                        code: codeBlockLines.joined(separator: "\n")
                    ))
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

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let headingMatch = parseHeading(trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: headingMatch.level, text: headingMatch.text))
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.horizontalRule)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                let quoteText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.blockquote(text: quoteText))
                continue
            }

            if let bulletItem = parseBulletListItem(line) {
                flushParagraph()
                if currentListType != .bullet {
                    flushList()
                    currentListType = .bullet
                }
                currentListItems.append(bulletItem)
                continue
            }

            if let numberedItem = parseNumberedListItem(line) {
                flushParagraph()
                if currentListType != .numbered {
                    flushList()
                    currentListType = .numbered
                }
                currentListItems.append(numberedItem)
                continue
            }

            currentParagraph.append(line)
        }

        if inCodeBlock {
            blocks.append(.codeBlock(
                language: codeBlockLanguage,
                code: codeBlockLines.joined(separator: "\n")
            ))
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
        var indent = 0
        var index = line.startIndex
        while index < line.endIndex && (line[index] == " " || line[index] == "\t") {
            indent += line[index] == "\t" ? 2 : 1
            index = line.index(after: index)
        }
        indent = indent / 2

        let remaining = String(line[index...])
        guard remaining.count >= 2 else { return nil }
        let firstChar = remaining.first
        guard firstChar == "-" || firstChar == "*" || firstChar == "+" else { return nil }

        let afterMarker = remaining.index(remaining.startIndex, offsetBy: 1)
        guard remaining[afterMarker] == " " else { return nil }

        let text = String(remaining[remaining.index(afterMarker, offsetBy: 1)...])
            .trimmingCharacters(in: .whitespaces)
        return ListItem(text: text, indent: indent)
    }

    private static func parseNumberedListItem(_ line: String) -> ListItem? {
        var indent = 0
        var index = line.startIndex
        while index < line.endIndex && (line[index] == " " || line[index] == "\t") {
            indent += line[index] == "\t" ? 2 : 1
            index = line.index(after: index)
        }
        indent = indent / 2

        let remaining = String(line[index...])
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)[.\)]\s+(.+)$"#),
              let match = regex.firstMatch(
                  in: remaining,
                  range: NSRange(remaining.startIndex..., in: remaining)
              ),
              let textRange = Range(match.range(at: 2), in: remaining) else {
            return nil
        }

        let text = String(remaining[textRange]).trimmingCharacters(in: .whitespaces)
        return ListItem(text: text, indent: indent)
    }
}

// MARK: - Inline Markdown Text

private struct InlineMarkdownText: View {
    let text: String
    let baseFont: Font

    init(_ text: String, baseFont: Font = Typography.body) {
        self.text = text
        self.baseFont = baseFont
    }

    var body: some View {
        Text(parse())
            .font(baseFont)
            .textSelection(.enabled)
            .lineSpacing(2)
    }

    private func parse() -> AttributedString {
        var result = AttributedString()

        let patterns: [(pattern: String, transform: (String) -> AttributedString)] = [
            // Bold + Code: **`text`**
            (#"\*\*`([^`]+)`\*\*"#, { match in
                var attr = AttributedString(match)
                attr.font = Typography.code.weight(.semibold)
                attr.backgroundColor = AppTheme.backgroundSecondary
                return attr
            }),
            // Code (backticks)
            (#"`([^`]+)`"#, { match in
                var attr = AttributedString(match)
                attr.font = Typography.code
                attr.backgroundColor = AppTheme.backgroundSecondary
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
            }),
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

// MARK: - Session Code Block View

private struct SessionCodeBlockView: View {
    let language: String?
    let code: String

    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(Typography.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(isCopied ? .green : AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .background(Color.black.opacity(0.3))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Typography.code)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(AppTheme.spacingS)
            }
        }
        .background(Color(white: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
    }
}

// MARK: - Session Markdown Text View

struct SessionMarkdownTextView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
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
            InlineMarkdownText(text, baseFont: Typography.body)
                .foregroundStyle(AppTheme.textPrimary)

        case .bulletList(let items):
            bulletListView(items: items)

        case .numberedList(let items):
            numberedListView(items: items)

        case .codeBlock(let language, let code):
            SessionCodeBlockView(language: language, code: code)

        case .horizontalRule:
            Divider()
                .padding(.vertical, AppTheme.spacingXS)

        case .blockquote(let text):
            blockquoteView(text: text)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: Typography.title2
        case 2: Typography.title3
        case 3: Typography.headline
        default: Typography.subheadline
        }

        InlineMarkdownText(text, baseFont: font)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.top, level <= 2 ? AppTheme.spacingS : AppTheme.spacingXS)
    }

    @ViewBuilder
    private func bulletListView(items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: AppTheme.spacingXS) {
                    Text("\u{2022}")
                        .font(Typography.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.leading, CGFloat(item.indent) * AppTheme.spacingM)

                    InlineMarkdownText(item.text, baseFont: Typography.body)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func numberedListView(items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: AppTheme.spacingXS) {
                    Text("\(index + 1).")
                        .font(Typography.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(minWidth: 20, alignment: .trailing)
                        .padding(.leading, CGFloat(item.indent) * AppTheme.spacingM)

                    InlineMarkdownText(item.text, baseFont: Typography.body)
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func blockquoteView(text: String) -> some View {
        HStack(spacing: AppTheme.spacingXS) {
            Rectangle()
                .fill(AppTheme.cardBorder)
                .frame(width: 3)

            InlineMarkdownText(text)
                .foregroundStyle(AppTheme.textSecondary)
                .italic()
        }
        .padding(.vertical, 2)
    }
}
