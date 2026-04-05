//
//  ChatInlineMarkdown.swift
//  unbound-macos
//
//  Shared inline markdown parser used by prose and table text rendering.
//

import Foundation

enum InlineToken: Equatable {
    case text(String)
    case bold(String)
    case italic(String)
    case code(String)
    case boldCode(String)
    case link(label: String, url: String)
    case strikethrough(String)
}

struct ChatInlineMarkdownOptions: Equatable {
    var parseLinks: Bool
    var parseStrikethrough: Bool

    static let prose = ChatInlineMarkdownOptions(parseLinks: true, parseStrikethrough: true)
    static let table = ChatInlineMarkdownOptions(parseLinks: false, parseStrikethrough: false)
}

enum ChatInlineMarkdown {
    private struct Match {
        let range: Range<String.Index>
        let token: InlineToken
    }

    static func parse(_ text: String, options: ChatInlineMarkdownOptions = .prose) -> [InlineToken] {
        var matches: [Match] = []

        // Deterministic precedence: boldCode -> link -> code -> strike -> bold -> italic.
        matches.append(contentsOf: captureSimple(text, pattern: #"\*\*`([^`]+)`\*\*"#, to: { .boldCode($0) }))
        if options.parseLinks {
            matches.append(contentsOf: captureLinks(text))
        }
        matches.append(contentsOf: captureSimple(text, pattern: #"`([^`]+)`"#, to: { .code($0) }))
        if options.parseStrikethrough {
            matches.append(contentsOf: captureSimple(text, pattern: #"~~([^~]+)~~"#, to: { .strikethrough($0) }))
        }
        matches.append(contentsOf: captureSimple(text, pattern: #"\*\*([^*]+)\*\*"#, to: { .bold($0) }))
        matches.append(contentsOf: captureSimple(text, pattern: #"__([^_]+)__"#, to: { .bold($0) }))
        matches.append(contentsOf: captureSimple(text, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, to: { .italic($0) }))
        matches.append(contentsOf: captureSimple(text, pattern: #"(?<!_)_([^_]+)_(?!_)"#, to: { .italic($0) }))

        matches.sort { $0.range.lowerBound < $1.range.lowerBound }

        var filtered: [Match] = []
        var lastEnd = text.startIndex
        for match in matches {
            if match.range.lowerBound >= lastEnd {
                filtered.append(match)
                lastEnd = match.range.upperBound
            }
        }

        var tokens: [InlineToken] = []
        var cursor = text.startIndex

        for match in filtered {
            if cursor < match.range.lowerBound {
                tokens.append(.text(String(text[cursor..<match.range.lowerBound])))
            }
            tokens.append(match.token)
            cursor = match.range.upperBound
        }

        if cursor < text.endIndex {
            tokens.append(.text(String(text[cursor...])))
        }

        return coalesceTextTokens(tokens)
    }

    private static func captureSimple(
        _ text: String,
        pattern: String,
        to style: (String) -> InlineToken
    ) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let full = Range(match.range, in: text),
                  let captured = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return Match(range: full, token: style(String(text[captured])))
        }
    }

    private static func captureLinks(_ text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let full = Range(match.range, in: text),
                  let label = Range(match.range(at: 1), in: text),
                  let url = Range(match.range(at: 2), in: text) else {
                return nil
            }
            return Match(
                range: full,
                token: .link(label: String(text[label]), url: String(text[url]))
            )
        }
    }

    private static func coalesceTextTokens(_ tokens: [InlineToken]) -> [InlineToken] {
        var result: [InlineToken] = []
        for token in tokens {
            switch token {
            case .text(let text):
                guard !text.isEmpty else { continue }
                if case .text(let previous)? = result.last {
                    result[result.count - 1] = .text(previous + text)
                } else {
                    result.append(token)
                }
            default:
                result.append(token)
            }
        }
        return result
    }
}
