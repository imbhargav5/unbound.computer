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
    case listHeading(text: String)
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
        case .listHeading(let text):
            return "lh-\(text.hashValue)"
        case .paragraph(let text):
            return "p-\(text.hashValue)"
        case .bulletList(let items):
            return "ul-\(items.map { $0.text }.joined().hashValue)"
        case .numberedList(let items):
            return "ol-\(items.map { "\($0.marker ?? "")\($0.text)" }.joined().hashValue)"
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
    let marker: String?

    init(text: String, indent: Int, marker: String? = nil) {
        self.text = text
        self.indent = indent
        self.marker = marker
    }
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

        return promoteListHeadings(in: blocks)
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
        return ListItem(text: text, indent: indent, marker: nil)
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

        // Match pattern: number+delimiter followed by whitespace and text.
        // We keep the source marker intact (e.g. "3." or "7)").
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+[\.\)])\s+(.+)$"#),
              let match = regex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
              let markerRange = Range(match.range(at: 1), in: remaining),
              let textRange = Range(match.range(at: 2), in: remaining) else {
            return nil
        }

        let marker = String(remaining[markerRange])
        let text = String(remaining[textRange]).trimmingCharacters(in: .whitespaces)
        return ListItem(text: text, indent: indent, marker: marker)
    }

    private static func promoteListHeadings(in blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        guard !blocks.isEmpty else { return blocks }

        var promoted: [MarkdownBlock] = []
        var index = 0

        while index < blocks.count {
            let current = blocks[index]

            if case .paragraph(let text) = current,
               isSingleLineParagraph(text),
               index + 1 < blocks.count,
               isListBlock(blocks[index + 1]) {
                promoted.append(.listHeading(text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                index += 1
                continue
            }

            promoted.append(current)
            index += 1
        }

        return promoted
    }

    private static func isSingleLineParagraph(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("\n")
    }

    private static func isListBlock(_ block: MarkdownBlock) -> Bool {
        switch block {
        case .bulletList, .numberedList:
            return true
        default:
            return false
        }
    }
}

// MARK: - Parser Debug Snapshot

struct MarkdownListDebugItem: Equatable {
    let text: String
    let indent: Int
    let marker: String?
}

enum MarkdownBlockDebug: Equatable {
    case heading(level: Int, text: String)
    case listHeading(text: String)
    case paragraph(text: String)
    case bulletList(items: [MarkdownListDebugItem])
    case numberedList(items: [MarkdownListDebugItem])
    case codeBlock(language: String?, code: String)
    case horizontalRule
    case blockquote(text: String)
}

enum MarkdownParserDebug {
    static func parse(_ text: String) -> [MarkdownBlockDebug] {
        MarkdownBlockParser.parse(text).map { block in
            switch block {
            case .heading(let level, let text):
                return .heading(level: level, text: text)
            case .listHeading(let text):
                return .listHeading(text: text)
            case .paragraph(let text):
                return .paragraph(text: text)
            case .bulletList(let items):
                return .bulletList(items: debugItems(from: items))
            case .numberedList(let items):
                return .numberedList(items: debugItems(from: items))
            case .codeBlock(let language, let code):
                return .codeBlock(language: language, code: code)
            case .horizontalRule:
                return .horizontalRule
            case .blockquote(let text):
                return .blockquote(text: text)
            }
        }
    }

    private static func debugItems(from items: [ListItem]) -> [MarkdownListDebugItem] {
        items.map { item in
            MarkdownListDebugItem(text: item.text, indent: item.indent, marker: item.marker)
        }
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

        case .listHeading(let text):
            listHeadingView(text: text)

        case .paragraph(let text):
            ChatInlineText(
                text: text,
                style: proseBodyStyle,
                colors: colors,
                options: .prose
            )

        case .bulletList(let items):
            bulletListView(items: items)

        case .numberedList(let items):
            numberedListView(items: items)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)

        case .horizontalRule:
            Rectangle()
                .fill(MarkdownProseTokens.horizontalRuleColor(colors: colors, colorScheme: colorScheme))
                .frame(height: MarkdownProseTokens.horizontalRuleHeight)
                .padding(.vertical, Spacing.sm)

        case .blockquote(let text):
            blockquoteView(text: text)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        ChatInlineText(
            text: text,
            style: proseHeadingStyle(level: level),
            colors: colors,
            options: .prose
        )
    }

    @ViewBuilder
    private func listHeadingView(text: String) -> some View {
        ChatInlineText(
            text: text,
            style: listHeadingStyle,
            colors: colors,
            options: .prose
        )
        .padding(.bottom, MarkdownListTokens.headingBottomSpacing)
    }

    @ViewBuilder
    private func bulletListView(items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: MarkdownListTokens.itemVerticalSpacing) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: MarkdownListTokens.markerToTextSpacing) {
                    Text("•")
                        .font(MarkdownListTokens.unorderedMarkerFont)
                        .foregroundStyle(colors.sidebarMeta)

                    ChatInlineText(
                        text: item.text,
                        style: listItemStyle,
                        colors: colors,
                        options: .prose
                    )
                }
                .padding(.leading, CGFloat(item.indent) * MarkdownListTokens.indentStep)
            }
        }
        .padding(.top, MarkdownListTokens.listPaddingTop)
        .padding(.trailing, MarkdownListTokens.listPaddingRight)
        .padding(.bottom, MarkdownListTokens.listPaddingBottom)
        .padding(.leading, MarkdownListTokens.listPaddingLeft)
    }

    @ViewBuilder
    private func numberedListView(items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: MarkdownListTokens.itemVerticalSpacing) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: MarkdownListTokens.markerToTextSpacing) {
                    Text(item.marker ?? "")
                        .font(MarkdownListTokens.orderedMarkerFont)
                        .foregroundStyle(colors.sidebarMeta)
                        .frame(width: MarkdownListTokens.orderedMarkerColumnWidth, alignment: .leading)

                    ChatInlineText(
                        text: item.text,
                        style: listItemStyle,
                        colors: colors,
                        options: .prose
                    )
                }
                .padding(.leading, CGFloat(item.indent) * MarkdownListTokens.indentStep)
            }
        }
        .padding(.top, MarkdownListTokens.listPaddingTop)
        .padding(.trailing, MarkdownListTokens.listPaddingRight)
        .padding(.bottom, MarkdownListTokens.listPaddingBottom)
        .padding(.leading, MarkdownListTokens.listPaddingLeft)
    }

    @ViewBuilder
    private func codeBlockView(language: String?, code: String) -> some View {
        MarkdownCodeBlockView(language: language, code: code, colors: colors)
    }

    @ViewBuilder
    private func blockquoteView(text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Rectangle()
                .fill(MarkdownProseTokens.blockquoteRailColor(colors: colors, colorScheme: colorScheme))
                .frame(width: MarkdownProseTokens.blockquoteRailWidth)

            ChatInlineText(
                text: text,
                style: blockquoteStyle,
                colors: colors,
                options: .prose
            )
        }
        .padding(.vertical, MarkdownProseTokens.blockquoteVerticalPadding)
        .padding(.horizontal, MarkdownProseTokens.blockquoteHorizontalPadding)
    }

    private var proseBodyStyle: ChatInlineRenderStyle {
        ChatInlineRenderStyle(
            baseFont: MarkdownProseTokens.paragraphFont,
            baseColor: MarkdownProseTokens.paragraphColor(colors: colors, colorScheme: colorScheme),
            boldColor: MarkdownProseTokens.boldColor(colors: colors, colorScheme: colorScheme),
            italicColor: MarkdownProseTokens.italicColor(colors: colors, colorScheme: colorScheme),
            linkColor: MarkdownProseTokens.linkColor(colors: colors, colorScheme: colorScheme),
            strikethroughColor: MarkdownProseTokens.strikethroughColor(colors: colors, colorScheme: colorScheme),
            lineSpacing: MarkdownProseTokens.paragraphLineSpacing,
            linksAreInteractive: true,
            enableTextSelection: true
        )
    }

    private var listHeadingStyle: ChatInlineRenderStyle {
        ChatInlineRenderStyle(
            baseFont: MarkdownListTokens.headingFont,
            baseColor: MarkdownListTokens.headingColor(colors: colors, colorScheme: colorScheme),
            boldColor: MarkdownListTokens.headingColor(colors: colors, colorScheme: colorScheme),
            italicColor: MarkdownListTokens.headingColor(colors: colors, colorScheme: colorScheme),
            linkColor: MarkdownProseTokens.linkColor(colors: colors, colorScheme: colorScheme),
            strikethroughColor: MarkdownProseTokens.strikethroughColor(colors: colors, colorScheme: colorScheme),
            lineSpacing: MarkdownListTokens.headingLineSpacing,
            linksAreInteractive: true,
            enableTextSelection: true
        )
    }

    private var listItemStyle: ChatInlineRenderStyle {
        ChatInlineRenderStyle(
            baseFont: MarkdownListTokens.itemTextFont,
            baseColor: colors.textMuted,
            boldColor: MarkdownProseTokens.boldColor(colors: colors, colorScheme: colorScheme),
            italicColor: MarkdownProseTokens.italicColor(colors: colors, colorScheme: colorScheme),
            linkColor: MarkdownProseTokens.linkColor(colors: colors, colorScheme: colorScheme),
            strikethroughColor: MarkdownProseTokens.strikethroughColor(colors: colors, colorScheme: colorScheme),
            lineSpacing: MarkdownProseTokens.paragraphLineSpacing,
            linksAreInteractive: true,
            enableTextSelection: true
        )
    }

    private var blockquoteStyle: ChatInlineRenderStyle {
        ChatInlineRenderStyle(
            baseFont: MarkdownProseTokens.paragraphFont.italic(),
            baseColor: MarkdownProseTokens.blockquoteTextColor(colors: colors, colorScheme: colorScheme),
            boldColor: MarkdownProseTokens.blockquoteTextColor(colors: colors, colorScheme: colorScheme),
            italicColor: MarkdownProseTokens.blockquoteTextColor(colors: colors, colorScheme: colorScheme),
            linkColor: MarkdownProseTokens.linkColor(colors: colors, colorScheme: colorScheme),
            strikethroughColor: MarkdownProseTokens.strikethroughColor(colors: colors, colorScheme: colorScheme),
            lineSpacing: MarkdownProseTokens.paragraphLineSpacing,
            linksAreInteractive: true,
            enableTextSelection: true
        )
    }

    private func proseHeadingStyle(level: Int) -> ChatInlineRenderStyle {
        let baseFont: Font
        let baseColor: Color

        switch level {
        case 1:
            baseFont = MarkdownProseTokens.headingH1Font
            baseColor = MarkdownProseTokens.headingH1Color(colors: colors, colorScheme: colorScheme)
        case 2:
            baseFont = MarkdownProseTokens.headingH2Font
            baseColor = MarkdownProseTokens.headingH2Color(colors: colors, colorScheme: colorScheme)
        default:
            baseFont = MarkdownProseTokens.headingH3Font
            baseColor = MarkdownProseTokens.headingH3Color(colors: colors, colorScheme: colorScheme)
        }

        return ChatInlineRenderStyle(
            baseFont: baseFont,
            baseColor: baseColor,
            boldColor: baseColor,
            italicColor: baseColor,
            linkColor: MarkdownProseTokens.linkColor(colors: colors, colorScheme: colorScheme),
            strikethroughColor: MarkdownProseTokens.strikethroughColor(colors: colors, colorScheme: colorScheme),
            lineSpacing: MarkdownProseTokens.headingLineSpacing,
            linksAreInteractive: true,
            enableTextSelection: true
        )
    }
}

// MARK: - Preview

#if DEBUG

#Preview("Pencil Lists (Tjnze + 5EFvs)") {
    ScrollView {
        MarkdownTextView(text: """
        Key Changes
        - Replace session-based auth with JWT access + refresh tokens
        - Add token rotation and automatic expiry handling
        - Ensure backward compatibility with existing API tests
        - Update middleware to validate tokens on each request

        Getting Started
        1. Clone the repository and install dependencies using npm
        2. Configure environment variables in the .env file
        3. Run database migrations to set up the schema
        4. Start the development server with npm run dev
        """)
        .padding()
    }
    .frame(width: 600, height: 320)
    .preferredColorScheme(.dark)
}

#endif
