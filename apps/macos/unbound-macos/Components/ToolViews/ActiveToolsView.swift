//
//  ActiveToolsView.swift
//  unbound-macos
//
//  Lightweight list for standalone ActiveTools (not inside a sub-agent).
//

import SwiftUI

struct ActiveToolsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tools: [ActiveTool]
    @State private var isExpanded: Bool

    init(tools: [ActiveTool], initiallyExpanded: Bool = true) {
        self.tools = tools
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var summaryText: String {
        ToolActivitySummary.summary(for: tools)
    }

    private var actionLines: [ToolActionLine] {
        ToolActivitySummary.actionLines(for: tools)
    }

    private var hasDetails: Bool {
        !actionLines.isEmpty
    }

    private var detailPaddingLeading: CGFloat {
        Spacing.md + IconSize.sm + Spacing.sm
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
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: IconSize.sm, height: IconSize.sm)

                    Text(summaryText)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    Spacer()

                    if hasDetails {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(colors.mutedForeground)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && hasDetails {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ShadcnDivider()
                        .padding(.horizontal, Spacing.md)

                    ForEach(actionLines) { line in
                        Text(line.text)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                            .padding(.leading, detailPaddingLeading)
                            .padding(.trailing, Spacing.md)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .background(colors.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(colors.panelDivider, lineWidth: BorderWidth.hairline)
        )
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        ActiveToolsView(tools: [
            ActiveTool(id: "t1", name: "Glob", inputPreview: "**/*.swift", status: .completed),
            ActiveTool(id: "t2", name: "Grep", inputPreview: "authenticate", status: .running),
            ActiveTool(id: "t3", name: "Read", inputPreview: "/src/auth/login.ts", status: .failed),
        ])

        ActiveToolsView(
            tools: [
                ActiveTool(id: "t4", name: "Read", inputPreview: "SessionDetailView.swift", status: .completed),
                ActiveTool(id: "t5", name: "Write", inputPreview: "ParserSpec.md", status: .completed),
            ],
            initiallyExpanded: false
        )
    }
    .frame(width: 450)
    .padding()
}
