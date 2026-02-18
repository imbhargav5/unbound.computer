//
//  ToolUseView.swift
//  unbound-macos
//
//  Display tool use with status and collapsible details
//

import SwiftUI

struct ToolUseView: View {
    let toolUse: ToolUse
    @State private var isExpanded: Bool

    init(toolUse: ToolUse, initiallyExpanded: Bool = false) {
        self.toolUse = toolUse
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    private var actionText: String {
        toolUse.toolName
    }

    private var subtitle: String? {
        parser.filePath
            ?? parser.pattern
            ?? parser.commandDescription
            ?? parser.command
            ?? parser.query
            ?? parser.url
    }

    private var detailsText: String? {
        if let output = toolUse.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            return output
        }
        if let input = toolUse.input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
            return input
        }
        return nil
    }

    private var hasDetails: Bool {
        detailsText != nil
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
        guard let detailsText else { return 0 }
        return max(1, detailsText.components(separatedBy: .newlines).count)
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

            if isExpanded, let detailsText {
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
    }
}

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
