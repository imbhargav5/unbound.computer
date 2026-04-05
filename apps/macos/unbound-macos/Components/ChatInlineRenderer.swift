//
//  ChatInlineRenderer.swift
//  unbound-macos
//
//  Shared wrap-capable inline renderer with exact inline-code chips.
//

import Dispatch
import Foundation
import SwiftUI

struct OversizedTextPolicy {
    let markdownParseCharLimit: Int
    let markdownParseLineLimit: Int
    let collapsedPreviewChars: Int
    let collapsedPreviewLines: Int
    let toolDetailPreviewChars: Int
    let toolDetailPreviewLines: Int

    static let aggressive = OversizedTextPolicy(
        markdownParseCharLimit: 12_000,
        markdownParseLineLimit: 400,
        collapsedPreviewChars: 4_000,
        collapsedPreviewLines: 120,
        toolDetailPreviewChars: 8_000,
        toolDetailPreviewLines: 200
    )

    func isOversizedMarkdown(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.count > markdownParseCharLimit {
            return true
        }
        return estimatedLineCount(in: text) > markdownParseLineLimit
    }

    func collapsedMarkdownPreview(for text: String) -> String {
        truncate(
            text: text,
            charLimit: collapsedPreviewChars,
            lineLimit: collapsedPreviewLines
        )
    }

    func needsToolDetailTruncation(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.count > toolDetailPreviewChars {
            return true
        }
        return estimatedLineCount(in: text) > toolDetailPreviewLines
    }

    func collapsedToolPreview(for text: String) -> String {
        truncate(
            text: text,
            charLimit: toolDetailPreviewChars,
            lineLimit: toolDetailPreviewLines
        )
    }

    private func truncate(text: String, charLimit: Int, lineLimit: Int) -> String {
        guard !text.isEmpty else { return "" }

        let head = String(text.prefix(charLimit))
        let lines = head.components(separatedBy: .newlines)
        let limitedLines = Array(lines.prefix(lineLimit))
        let truncated = limitedLines.joined(separator: "\n")

        let exceededChars = text.count > charLimit
        let exceededLines = estimatedLineCount(in: text) > lineLimit
        if exceededChars || exceededLines {
            return "\(truncated)\n\n... (truncated for performance)"
        }

        return truncated
    }

    private func estimatedLineCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }
}

@MainActor
final class SessionTextRenderCache {
    enum ParseMode: String {
        case markdownBlocks
        case tableSegments
        case tableAwareSegments
        case textDisplay
        case planParse
        case inlineTokens
        case inlineRuns
        case inlineAttributed
    }

    struct Key: Hashable {
        let mode: ParseMode
        let textHash: Int
        let textLength: Int
        let colorSchemeSensitive: Bool
        let colorSchemeBucket: Int
        let extra: Int
    }

    private struct Entry {
        var value: Any
        var estimatedCost: Int
    }

    static let shared = SessionTextRenderCache()

    private let maxEntryCount = 600
    private let maxEstimatedCost = 12_000_000

    private var storage: [Key: Entry] = [:]
    private var lruOrder: [Key] = []
    private var totalEstimatedCost = 0

    #if os(macOS)
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    #endif

    private init() {
        #if os(macOS)
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.removeAll(reason: "memoryPressure")
        }
        source.resume()
        memoryPressureSource = source
        #endif
    }

    deinit {
        #if os(macOS)
        memoryPressureSource?.cancel()
        #endif
    }

    static func makeKey(
        mode: ParseMode,
        text: String,
        colorSchemeSensitive: Bool = false,
        colorScheme: ColorScheme? = nil,
        extra: Int = 0
    ) -> Key {
        Key(
            mode: mode,
            textHash: text.hashValue,
            textLength: text.utf8.count,
            colorSchemeSensitive: colorSchemeSensitive,
            colorSchemeBucket: colorSchemeSensitive ? (colorScheme?.cacheBucket ?? -1) : -1,
            extra: extra
        )
    }

    func value<T>(
        for key: Key,
        estimatedCost: Int,
        build: () -> T
    ) -> T {
        if let existing = storage[key], let typed = existing.value as? T {
            touch(key)
            return typed
        }

        if let existing = storage[key], existing.value is T == false {
            removeValue(for: key)
        }

        let interval = ChatPerformanceSignposts.beginInterval(
            "chat.textCache.miss",
            "\(key.mode.rawValue) bytes=\(key.textLength)"
        )
        let built = build()
        ChatPerformanceSignposts.endInterval(interval, key.mode.rawValue)

        insert(
            value: built,
            for: key,
            estimatedCost: max(1, estimatedCost)
        )
        return built
    }

    func removeAll(reason: String = "manual") {
        storage.removeAll(keepingCapacity: true)
        lruOrder.removeAll(keepingCapacity: true)
        totalEstimatedCost = 0
        ChatPerformanceSignposts.event("chat.textCache.clear", reason)
    }

    private func insert(value: Any, for key: Key, estimatedCost: Int) {
        if let existing = storage[key] {
            totalEstimatedCost -= existing.estimatedCost
        } else {
            lruOrder.append(key)
        }

        storage[key] = Entry(value: value, estimatedCost: estimatedCost)
        totalEstimatedCost += estimatedCost
        evictIfNeeded()
    }

    private func touch(_ key: Key) {
        guard let index = lruOrder.firstIndex(of: key) else { return }
        lruOrder.remove(at: index)
        lruOrder.append(key)
    }

    private func removeValue(for key: Key) {
        if let removed = storage.removeValue(forKey: key) {
            totalEstimatedCost -= removed.estimatedCost
        }
        if let index = lruOrder.firstIndex(of: key) {
            lruOrder.remove(at: index)
        }
    }

    private func evictIfNeeded() {
        while storage.count > maxEntryCount || totalEstimatedCost > maxEstimatedCost {
            guard let oldest = lruOrder.first else { break }
            removeValue(for: oldest)
        }
    }
}

private extension ColorScheme {
    var cacheBucket: Int {
        switch self {
        case .light:
            return 0
        case .dark:
            return 1
        @unknown default:
            return 2
        }
    }
}

struct ChatInlineRenderStyle {
    let baseFont: Font
    let baseColor: Color
    let boldColor: Color
    let italicColor: Color
    let linkColor: Color
    let strikethroughColor: Color
    let lineSpacing: CGFloat
    let linksAreInteractive: Bool
    let enableTextSelection: Bool
}

private struct ChatInlineRun: Identifiable {
    enum Kind: Equatable {
        case text
        case bold
        case italic
        case code
        case boldCode
        case link(url: String)
        case strikethrough
    }

    let id: String
    let kind: Kind
    let text: String
}

struct ChatInlineText: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let style: ChatInlineRenderStyle
    let options: ChatInlineMarkdownOptions
    let colors: ThemeColors

    init(
        text: String,
        style: ChatInlineRenderStyle,
        colors: ThemeColors,
        options: ChatInlineMarkdownOptions = .prose
    ) {
        self.text = text
        self.style = style
        self.options = options
        self.colors = colors
    }

    private var optionsSignature: Int {
        var hasher = Hasher()
        hasher.combine(options.parseLinks)
        hasher.combine(options.parseStrikethrough)
        return hasher.finalize()
    }

    private var styleSignature: Int {
        var hasher = Hasher()
        hasher.combine(style.lineSpacing)
        hasher.combine(style.linksAreInteractive)
        hasher.combine(style.enableTextSelection)
        hasher.combine(String(describing: style.baseFont))
        hasher.combine(String(describing: style.baseColor))
        hasher.combine(String(describing: style.boldColor))
        hasher.combine(String(describing: style.italicColor))
        hasher.combine(String(describing: style.linkColor))
        hasher.combine(String(describing: style.strikethroughColor))
        return hasher.finalize()
    }

    private var inlineTokens: [InlineToken] {
        let key = SessionTextRenderCache.makeKey(
            mode: .inlineTokens,
            text: text,
            extra: optionsSignature
        )

        return SessionTextRenderCache.shared.value(
            for: key,
            estimatedCost: max(128, text.utf8.count)
        ) {
            let interval = ChatPerformanceSignposts.beginInterval(
                "chat.inline.tokenize",
                "chars=\(text.count)"
            )
            let tokens = ChatInlineMarkdown.parse(text, options: options)
            ChatPerformanceSignposts.endInterval(interval, "tokens=\(tokens.count)")
            return tokens
        }
    }

    private var runs: [ChatInlineRun] {
        let key = SessionTextRenderCache.makeKey(
            mode: .inlineRuns,
            text: text,
            extra: optionsSignature
        )

        return SessionTextRenderCache.shared.value(
            for: key,
            estimatedCost: max(256, text.utf8.count * 2)
        ) {
            inlineTokens.enumerated().flatMap { tokenIndex, token in
                expandRuns(for: token, tokenIndex: tokenIndex)
            }
        }
    }

    private var containsInlineCodeToken: Bool {
        inlineTokens.contains { token in
            switch token {
            case .code, .boldCode:
                return true
            default:
                return false
            }
        }
    }

    private var attributedInlineText: AttributedString {
        let key = SessionTextRenderCache.makeKey(
            mode: .inlineAttributed,
            text: text,
            colorSchemeSensitive: true,
            colorScheme: colorScheme,
            extra: optionsSignature ^ styleSignature
        )

        return SessionTextRenderCache.shared.value(
            for: key,
            estimatedCost: max(256, text.utf8.count * 2)
        ) {
            buildAttributedInlineText()
        }
    }

    var body: some View {
        let content = containsInlineCodeToken
            ? AnyView(
                ChatInlineFlowLayout(lineSpacing: style.lineSpacing, itemSpacing: 0) {
                    ForEach(runs) { run in
                        runView(run)
                    }
                }
            )
            : AnyView(
                Text(attributedInlineText)
                    .lineSpacing(style.lineSpacing)
            )

        if style.enableTextSelection {
            content.textSelection(.enabled)
        } else {
            content
        }
    }

    @ViewBuilder
    private func runView(_ run: ChatInlineRun) -> some View {
        switch run.kind {
        case .text:
            Text(run.text)
                .font(style.baseFont)
                .foregroundStyle(style.baseColor)

        case .bold:
            Text(run.text)
                .font(style.baseFont.weight(.bold))
                .foregroundStyle(style.boldColor)

        case .italic:
            Text(run.text)
                .font(style.baseFont.italic())
                .foregroundStyle(style.italicColor)

        case .strikethrough:
            Text(run.text)
                .font(style.baseFont)
                .foregroundStyle(style.strikethroughColor)
                .strikethrough(true, color: style.strikethroughColor)

        case .link(let urlString):
            if style.linksAreInteractive, let url = URL(string: urlString) {
                Button {
                    openURL(url)
                } label: {
                    Text(run.text)
                        .font(style.baseFont)
                        .foregroundStyle(style.linkColor)
                }
                .buttonStyle(.plain)
            } else {
                Text(run.text)
                    .font(style.baseFont)
                    .foregroundStyle(style.linkColor)
            }

        case .code, .boldCode:
            Text(run.text)
                .font(MarkdownProseTokens.inlineCodeFont)
                .foregroundStyle(MarkdownProseTokens.inlineCodeTextColor(colors: colors, colorScheme: colorScheme))
                .padding(.vertical, MarkdownProseTokens.inlineCodePaddingVertical)
                .padding(.horizontal, MarkdownProseTokens.inlineCodePaddingHorizontal)
                .background(
                    RoundedRectangle(cornerRadius: MarkdownProseTokens.inlineCodeCornerRadius)
                        .fill(MarkdownProseTokens.inlineCodeBackground(colors: colors, colorScheme: colorScheme))
                )
        }
    }

    private func expandRuns(for token: InlineToken, tokenIndex: Int) -> [ChatInlineRun] {
        switch token {
        case .text(let value):
            return splitTextRuns(value).enumerated().map { runIndex, runText in
                ChatInlineRun(id: "t-\(tokenIndex)-\(runIndex)", kind: .text, text: runText)
            }
        case .bold(let value):
            return splitTextRuns(value).enumerated().map { runIndex, runText in
                ChatInlineRun(id: "b-\(tokenIndex)-\(runIndex)", kind: .bold, text: runText)
            }
        case .italic(let value):
            return splitTextRuns(value).enumerated().map { runIndex, runText in
                ChatInlineRun(id: "i-\(tokenIndex)-\(runIndex)", kind: .italic, text: runText)
            }
        case .code(let value):
            return [ChatInlineRun(id: "c-\(tokenIndex)-0", kind: .code, text: value)]
        case .boldCode(let value):
            return [ChatInlineRun(id: "bc-\(tokenIndex)-0", kind: .boldCode, text: value)]
        case .strikethrough(let value):
            return splitTextRuns(value).enumerated().map { runIndex, runText in
                ChatInlineRun(id: "s-\(tokenIndex)-\(runIndex)", kind: .strikethrough, text: runText)
            }
        case .link(let label, let url):
            return splitTextRuns(label).enumerated().map { runIndex, runText in
                ChatInlineRun(id: "l-\(tokenIndex)-\(runIndex)", kind: .link(url: url), text: runText)
            }
        }
    }

    private func buildAttributedInlineText() -> AttributedString {
        var output = AttributedString()

        for token in inlineTokens {
            switch token {
            case .text(let value):
                output.append(styledSegment(text: value, kind: .text))
            case .bold(let value):
                output.append(styledSegment(text: value, kind: .bold))
            case .italic(let value):
                output.append(styledSegment(text: value, kind: .italic))
            case .code(let value):
                output.append(styledSegment(text: value, kind: .code))
            case .boldCode(let value):
                output.append(styledSegment(text: value, kind: .boldCode))
            case .link(let label, let url):
                output.append(styledSegment(text: label, kind: .link(url: url)))
            case .strikethrough(let value):
                output.append(styledSegment(text: value, kind: .strikethrough))
            }
        }

        return output
    }

    private func styledSegment(text: String, kind: ChatInlineRun.Kind) -> AttributedString {
        var segment = AttributedString(text)
        switch kind {
        case .text:
            segment.font = style.baseFont
            segment.foregroundColor = style.baseColor

        case .bold:
            segment.font = style.baseFont.weight(.bold)
            segment.foregroundColor = style.boldColor

        case .italic:
            segment.font = style.baseFont.italic()
            segment.foregroundColor = style.italicColor

        case .strikethrough:
            segment.font = style.baseFont
            segment.foregroundColor = style.strikethroughColor

        case .link(let urlString):
            segment.font = style.baseFont
            segment.foregroundColor = style.linkColor
            if style.linksAreInteractive, let url = URL(string: urlString) {
                segment.link = url
            }

        case .code, .boldCode:
            segment.font = MarkdownProseTokens.inlineCodeFont
            segment.foregroundColor = MarkdownProseTokens.inlineCodeTextColor(
                colors: colors,
                colorScheme: colorScheme
            )
        }

        return segment
    }

    private func splitTextRuns(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(pattern: #"\S+|\s+"#) else { return [text] }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let segment = String(text[range]).replacingOccurrences(of: "\n", with: " ")
            return segment.isEmpty ? nil : segment
        }
    }
}

private struct ChatInlineFlowLayout: Layout {
    let lineSpacing: CGFloat
    let itemSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, x - itemSpacing)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            x += size.width + itemSpacing
            rowHeight = max(rowHeight, size.height)
        }

        maxRowWidth = max(maxRowWidth, max(0, x - itemSpacing))
        return CGSize(width: proposal.width ?? maxRowWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard !subviews.isEmpty else { return }

        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + itemSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
