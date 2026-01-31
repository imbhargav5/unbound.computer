//
//  ActiveToolsView.swift
//  unbound-macos
//
//  Renders a list of standalone ActiveTools (not inside a sub-agent).
//

import SwiftUI

struct ActiveToolsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tools: [ActiveTool]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tools, id: \.id) { tool in
                ActiveToolRow(tool: tool)

                if tool.id != tools.last?.id {
                    ShadcnDivider()
                        .padding(.horizontal, Spacing.md)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }
}

#Preview {
    ActiveToolsView(tools: [
        ActiveTool(id: "t1", name: "Glob", inputPreview: "**/*.swift", status: .completed),
        ActiveTool(id: "t2", name: "Grep", inputPreview: "authenticate", status: .running),
        ActiveTool(id: "t3", name: "Read", inputPreview: "/src/auth/login.ts", status: .failed)
    ])
    .frame(width: 450)
    .padding()
}
