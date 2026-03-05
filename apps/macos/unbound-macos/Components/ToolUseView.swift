//
//  ToolUseView.swift
//  unbound-macos
//
//  Display tool use with status and collapsible details
//

import SwiftUI

struct ToolUseView: View {
    private static let oversizedPolicy = OversizedTextPolicy.aggressive

    let toolUse: ToolUse
    private let renderSnapshot: ToolRenderSnapshot?
    private let parser: ToolInputParser
    private let outputParser: ToolOutputParser
    @State private var isExpanded: Bool
    @State private var showFullDetails: Bool

    init(toolUse: ToolUse, initiallyExpanded: Bool = false) {
        self.toolUse = toolUse
        self.renderSnapshot = nil
        self.parser = ToolInputParser(toolUse.input)
        self.outputParser = ToolOutputParser(toolUse.output)
        _isExpanded = State(initialValue: initiallyExpanded)
        _showFullDetails = State(initialValue: false)
    }

    init(toolUse: ToolUse, renderSnapshot: ToolRenderSnapshot, initiallyExpanded: Bool = false) {
        self.toolUse = toolUse
        self.renderSnapshot = renderSnapshot
        self.parser = ToolInputParser(toolUse.input)
        self.outputParser = ToolOutputParser(toolUse.output)
        _isExpanded = State(initialValue: initiallyExpanded)
        _showFullDetails = State(initialValue: false)
    }

    private var actionText: String {
        toolUse.toolName
    }

    private var subtitle: String? {
        if let subtitle = renderSnapshot?.subtitle {
            return subtitle
        }

        return parser.filePath
            ?? parser.pattern
            ?? parser.commandDescription
            ?? parser.command
            ?? parser.query
            ?? parser.url
    }

    private var hasInputDetails: Bool {
        guard let input = toolUse.input else { return false }
        return input.unicodeScalars.contains { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }

    private var expandedDetailsText: String? {
        if outputParser.hasVisibleContent, let output = toolUse.output {
            guard Self.oversizedPolicy.needsToolDetailTruncation(output) else {
                return output
            }
            return showFullDetails ? output : Self.oversizedPolicy.collapsedToolPreview(for: output)
        }
        if hasInputDetails, let input = toolUse.input?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return input
        }
        return nil
    }

    private var hasDetails: Bool {
        outputParser.hasVisibleContent || hasInputDetails
    }

    private var showsExpandDetailsButton: Bool {
        guard outputParser.hasVisibleContent, let output = toolUse.output else { return false }
        return Self.oversizedPolicy.needsToolDetailTruncation(output)
    }

    private var toolIcon: String {
        ToolIcon.icon(for: toolUse.toolName)
    }

    private var statusName: String {
        switch toolUse.status {
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        switch toolUse.status {
        case .running: return Color(hex: "4A4A4A")
        case .completed: return Color(hex: "4A4A4A")
        case .failed: return Color(hex: "EF4444")
        }
    }

    private var detailLineCount: Int {
        if let renderSnapshot {
            return renderSnapshot.detailLineCount
        }

        if outputParser.hasVisibleContent {
            return outputParser.lineCount
        }
        guard let detailsText = expandedDetailsText, !detailsText.isEmpty else { return 0 }
        return detailsText.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }

    private var headerIconColor: Color {
        isExpanded ? Color(hex: "F59E0B") : Color(hex: "6B6B6B")
    }

    private var headerTitleColor: Color {
        isExpanded ? Color(hex: "E5E5E5") : Color(hex: "A0A0A0")
    }

    @ViewBuilder
    private var leadingChevronWhenExpanded: some View {
        if hasDetails, isExpanded {
            Image(systemName: "chevron.down")
                .font(.system(size: IconSize.xs))
                .foregroundStyle(Color(hex: "6B6B6B"))
                .frame(width: 12, height: 12)
        }
    }

    @ViewBuilder
    private var trailingChevronWhenCollapsed: some View {
        if hasDetails, !isExpanded {
            Image(systemName: "chevron.right")
                .font(.system(size: IconSize.xs))
                .foregroundStyle(Color(hex: "6B6B6B"))
                .frame(width: 12, height: 12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasDetails {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    HStack(alignment: .center, spacing: Spacing.sm) {
                        leadingChevronWhenExpanded

                        Image(systemName: toolIcon)
                            .font(.system(size: 12))
                            .foregroundStyle(headerIconColor)
                            .frame(width: 14, height: 14)

                        Text(actionText)
                            .font(Typography.terminal)
                            .fontWeight(.medium)
                            .foregroundStyle(headerTitleColor)
                            .lineLimit(1)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(Typography.mono)
                                .foregroundStyle(Color(hex: "6B6B6B"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    Text(statusName)
                        .font(Typography.mono)
                        .foregroundStyle(statusColor)

                    trailingChevronWhenCollapsed
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isExpanded, let detailsText = expandedDetailsText {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ScrollView {
                        Text(detailsText)
                            .font(Typography.mono)
                            .foregroundStyle(Color(hex: "8A8A8A"))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)

                    HStack {
                        if showsExpandDetailsButton {
                            Button(showFullDetails ? "Show less" : "Show full output") {
                                withAnimation(.easeInOut(duration: Duration.fast)) {
                                    showFullDetails.toggle()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(Typography.micro)
                            .foregroundStyle(Color(hex: "8A8A8A"))
                        }

                        Spacer()
                        Text("\(detailLineCount) line\(detailLineCount == 1 ? "" : "s")")
                            .font(Typography.micro)
                            .foregroundStyle(Color(hex: "4A4A4A"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(hex: "0D0D0D"))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "2A2A2A"))
                        .frame(height: 1)
                }
            }
        }
        .background(Color(hex: "111111"))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(hex: "2A2A2A"), lineWidth: BorderWidth.default)
        )
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                showFullDetails = false
            }
        }
        .onChange(of: toolUse.id) { _, _ in
            showFullDetails = false
        }
    }
}

#if DEBUG

#Preview {
    VStack(spacing: Spacing.md) {
        ToolUseView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Read",
            input: "src/main.swift",
            output: "File contents here...",
            status: .completed
        ), initiallyExpanded: true)

        ToolUseView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Bash",
            input: "npm test",
            output: nil,
            status: .running
        ))

        ToolUseView(toolUse: ToolUse(
            toolUseId: "test-3",
            toolName: "Bash",
            input: "swift build",
            output: "Error: Missing dependency",
            status: .failed
        ), initiallyExpanded: true)
    }
    .frame(width: 500)
    .padding()
}

#endif
