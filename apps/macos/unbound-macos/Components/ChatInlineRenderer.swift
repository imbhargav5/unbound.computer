//
//  ChatInlineRenderer.swift
//  unbound-macos
//
//  Shared wrap-capable inline renderer with exact inline-code chips.
//

import Foundation
import SwiftUI

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

    let id = UUID()
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

    private var runs: [ChatInlineRun] {
        let tokens = ChatInlineMarkdown.parse(text, options: options)
        return tokens.flatMap(expandRuns(for:))
    }

    var body: some View {
        let content = ChatInlineFlowLayout(lineSpacing: style.lineSpacing, itemSpacing: 0) {
            ForEach(runs) { run in
                runView(run)
            }
        }

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

    private func expandRuns(for token: InlineToken) -> [ChatInlineRun] {
        switch token {
        case .text(let value):
            return splitTextRuns(value).map { ChatInlineRun(kind: .text, text: $0) }
        case .bold(let value):
            return splitTextRuns(value).map { ChatInlineRun(kind: .bold, text: $0) }
        case .italic(let value):
            return splitTextRuns(value).map { ChatInlineRun(kind: .italic, text: $0) }
        case .code(let value):
            return [ChatInlineRun(kind: .code, text: value)]
        case .boldCode(let value):
            return [ChatInlineRun(kind: .boldCode, text: value)]
        case .strikethrough(let value):
            return splitTextRuns(value).map { ChatInlineRun(kind: .strikethrough, text: $0) }
        case .link(let label, let url):
            return splitTextRuns(label).map { ChatInlineRun(kind: .link(url: url), text: $0) }
        }
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
