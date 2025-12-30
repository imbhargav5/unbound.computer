//
//  CodeBlockView.swift
//  rocketry-macos
//
//  Display code blocks with syntax highlighting and copy button
//

import SwiftUI

struct CodeBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    let codeBlock: CodeBlock
    @State private var isCopied = false
    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if !codeBlock.language.isEmpty {
                    Text(codeBlock.language)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }

                if let filename = codeBlock.filename {
                    Text(filename)
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

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code)
                    .font(Typography.code)
                    .foregroundStyle(colors.foreground)
                    .textSelection(.enabled)
                    .padding(Spacing.md)
            }
            .background(colors.card)
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
        NSPasteboard.general.setString(codeBlock.code, forType: .string)

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

#Preview {
    CodeBlockView(codeBlock: CodeBlock(
        language: "swift",
        code: """
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }

        let message = greet(name: "World")
        print(message)
        """,
        filename: "Greeting.swift"
    ))
    .frame(width: 500)
    .padding()
}
