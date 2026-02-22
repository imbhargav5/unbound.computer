//
//  PlanModeCardView.swift
//  unbound-macos
//
//  Plan-mode response card matching Pencil components:
//  - DTkpt: collapsed
//  - 7MUaJ: expanded
//

import AppKit
import SwiftUI

enum PlanModeMessageParser {
    struct ParsedPlan: Equatable {
        let title: String
        let bodyMarkdown: String
    }

    static func parse(_ rawText: String) -> ParsedPlan? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, looksLikePlanContent(trimmed) else {
            return nil
        }

        let lines = trimmed.components(separatedBy: .newlines)

        var title = ""
        var bodyStartIndex = 0
        for (index, line) in lines.enumerated() {
            let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }

            title = headingText(from: candidate) ?? candidate
            bodyStartIndex = index + 1
            break
        }

        guard !title.isEmpty else { return nil }

        let body = lines
            .dropFirst(bodyStartIndex)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let bodyMarkdown = body.isEmpty ? trimmed : body
        return ParsedPlan(title: title, bodyMarkdown: bodyMarkdown)
    }

    private static func looksLikePlanContent(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasPlanHeading = text.range(
            of: #"(?m)^#{1,4}\s+.*plan.*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let hasImplementationSection = lower.contains("implementation plan")
        let hasNumberedSteps = text.range(
            of: #"(?m)^\s*\d+\.\s+\S+"#,
            options: .regularExpression
        ) != nil
        let hasSectionHeading = text.range(
            of: #"(?m)^#{2,6}\s+\S+"#,
            options: .regularExpression
        ) != nil

        return (hasPlanHeading || hasImplementationSection) && hasSectionHeading && hasNumberedSteps
    }

    private static func headingText(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^#{1,6}\s+(.+)$"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }

        return line[range].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PlanModeCardView: View {
    private enum Tokens {
        static let collapsedBodyHeight: CGFloat = 420
        static let cornerRadius: CGFloat = 12
        static let headerVerticalPadding: CGFloat = 10
        static let headerHorizontalPadding: CGFloat = 14
        static let bodyPadding: CGFloat = 20
    }

    let rawText: String
    let parsedPlan: PlanModeMessageParser.ParsedPlan
    var onApplyPlan: (() -> Void)? = nil
    var onRejectPlan: (() -> Void)? = nil

    @State private var isExpanded: Bool = false
    @State private var justCopied: Bool = false

    private var shouldCollapseByDefault: Bool {
        let lineCount = parsedPlan.bodyMarkdown.components(separatedBy: .newlines).count
        return lineCount > 14 || parsedPlan.bodyMarkdown.count > 700
    }

    private var canCollapse: Bool {
        shouldCollapseByDefault
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            card
        }
        .padding(16)
        .background(Color(hex: "0F0F0F"))
        .onAppear {
            if !canCollapse {
                isExpanded = true
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if canCollapse && !isExpanded {
                collapsedBody
            } else {
                expandedBody
                footer
            }
        }
        .background(Color(hex: "141414"))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                .stroke(Color(hex: "2A2A2A"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Plan")
                .font(GeistFont.sans(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "60A5FA"))

            Spacer()

            HStack(spacing: 12) {
                iconButton(systemName: "arrow.down.to.line", action: {})
                iconButton(systemName: justCopied ? "checkmark" : "doc.on.doc", action: copyPlanToClipboard)
                iconButton(systemName: isExpanded ? "chevron.up" : "chevron.down", action: toggleExpanded)
            }
        }
        .padding(.vertical, Tokens.headerVerticalPadding)
        .padding(.horizontal, Tokens.headerHorizontalPadding)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "2A2A2A"))
                .frame(height: 1)
        }
    }

    private var collapsedBody: some View {
        bodyContent
            .frame(height: Tokens.collapsedBodyHeight, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                Button(action: toggleExpanded) {
                    LinearGradient(
                        colors: [Color(hex: "141414").opacity(0), Color(hex: "141414")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)
                    .overlay(alignment: .bottom) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "4A4A4A"))
                            .padding(.bottom, 10)
                    }
                }
                .buttonStyle(.plain)
            }
    }

    private var expandedBody: some View {
        bodyContent
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(parsedPlan.title)
                .font(GeistFont.sans(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: "F5F5F5"))
                .fixedSize(horizontal: false, vertical: true)

            TextContentView(
                textContent: TextContent(text: parsedPlan.bodyMarkdown),
                isAssistantMessage: false
            )
            .foregroundStyle(Color(hex: "B3B3B3"))
        }
        .padding(Tokens.bodyPadding)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                onRejectPlan?()
            } label: {
                Text("Reject")
                    .font(GeistFont.sans(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "9A9A9A"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "3A3A3A"), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                onApplyPlan?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Apply Plan")
                        .font(GeistFont.sans(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "60A5FA"))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(hex: "2A2A2A"))
                .frame(height: 1)
        }
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "525252"))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: Duration.fast)) {
            isExpanded.toggle()
        }
    }

    private func copyPlanToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawText, forType: .string)

        withAnimation(.easeInOut(duration: Duration.fast)) {
            justCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: Duration.fast)) {
                justCopied = false
            }
        }
    }
}

#if DEBUG

#Preview("Plan Mode Card - Collapsed") {
    let text = """
    ## Fix macOS Todo Card Dupes by Merging TodoWrite State

    ### Summary
    `TodoWrite` payloads do not include a stable identifier.

    ### Public API / Type Changes
    1. Update `TodoList` in `ClaudeModels.swift`.

    ### Implementation Plan
    1. Change `TodoWrite` mapping behavior.
    2. Add dedupe + merge logic.
    3. Update rendering and tests.
    """

    if let parsed = PlanModeMessageParser.parse(text) {
        PlanModeCardView(rawText: text, parsedPlan: parsed)
            .frame(width: 620)
            .preferredColorScheme(.dark)
    }
}

#endif
