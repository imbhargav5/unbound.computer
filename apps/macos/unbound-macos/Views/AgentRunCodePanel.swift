//
//  AgentRunCodePanel.swift
//  unbound-macos
//
//  Low-glare raw JSON and NDJSON presentation for agent run details.
//

import AppKit
import Foundation
import SwiftUI

enum RunJSONFormatter {
    static func format(_ value: AnyCodableValue) -> String {
        prettyPrintedString(for: value.value) ?? String(describing: value.value)
    }

    static func formatJSONText(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return text
        }

        return prettyPrintedString(for: object) ?? text
    }

    static func rawText(_ text: String) -> String {
        text
    }

    private static func prettyPrintedString(for object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }
}

struct AgentRunCodePanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let text: String
    let language: String
    let badgeText: String?
    let maxHeight: CGFloat

    @State private var isCopied = false
    @State private var isHovered = false

    init(
        title: String,
        text: String,
        language: String = "json",
        badgeText: String? = nil,
        maxHeight: CGFloat
    ) {
        self.title = title
        self.text = text
        self.language = language
        self.badgeText = badgeText
        self.maxHeight = maxHeight
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var headerBadgeText: String {
        if let badgeText, !badgeText.isEmpty {
            return badgeText
        }

        return language.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.captionMedium)
                    .foregroundStyle(colors.cardForeground)

                Text(headerBadgeText)
                    .font(Typography.micro)
                    .foregroundStyle(colors.mutedForeground)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(colors.accent)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: IconSize.sm))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(isCopied ? colors.success : colors.mutedForeground)
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isCopied ? 1 : 0.72)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(colors.muted)

            ScrollView(.horizontal, showsIndicators: true) {
                ScrollView(.vertical, showsIndicators: true) {
                    HighlightedCodeText(code: text, language: language)
                        .lineSpacing(4)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: maxHeight)
            }
            .background(colors.chatBackground)
        }
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
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation(.easeInOut(duration: Duration.fast)) {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isCopied = false
            }
        }
    }
}
