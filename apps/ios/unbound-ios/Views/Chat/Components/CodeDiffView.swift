import SwiftUI

struct CodeDiffView: View {
    @Binding var diff: CodeDiff
    var onCopy: (() -> Void)?

    @State private var showCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingS) {
            ClaudeAvatarView(size: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 0) {
                // File header
                DiffHeaderView(
                    filename: diff.filename,
                    language: diff.language,
                    isExpanded: $diff.isExpanded,
                    showCopied: showCopied,
                    onCopy: handleCopy
                )

                // Diff content (collapsible)
                if diff.isExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(diff.hunks) { hunk in
                                DiffHunkView(hunk: hunk)
                            }
                        }
                        .frame(minWidth: 280)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(AppTheme.diffBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            Spacer(minLength: 20)
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    private func handleCopy() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Copy all diff content to clipboard
        let diffText = diff.hunks.flatMap { hunk in
            hunk.lines.map { line in
                "\(line.type.rawValue)\(line.content)"
            }
        }.joined(separator: "\n")

        UIPasteboard.general.string = diffText

        withAnimation(.easeInOut(duration: 0.2)) {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopied = false
            }
        }

        onCopy?()
    }
}

// MARK: - Diff Header

struct DiffHeaderView: View {
    let filename: String
    let language: String
    @Binding var isExpanded: Bool
    let showCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.spacingS) {
            // File icon
            Image(systemName: "doc.text.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            // Filename
            Text(filename)
                .font(.caption.weight(.medium).monospaced())
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Spacer()

            // Language badge
            Text(language)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())

            // Copy button
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                    if showCopied {
                        Text("Copied")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(showCopied ? .green : .white.opacity(0.6))
            }
            .buttonStyle(.plain)

            // Expand/collapse button
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()

                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.spacingS)
        .padding(.vertical, AppTheme.spacingS)
        .background(AppTheme.diffHeaderBg)
    }
}

// MARK: - Diff Hunk

struct DiffHunkView: View {
    let hunk: CodeDiff.DiffHunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk header (optional)
            if let header = hunk.header {
                Text(header)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.7))
                    .padding(.horizontal, AppTheme.spacingS)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cyan.opacity(0.1))
            }

            // Diff lines
            ForEach(hunk.lines) { line in
                DiffLineView(line: line)
            }
        }
    }
}

// MARK: - Diff Line

struct DiffLineView: View {
    let line: CodeDiff.DiffLine

    private var backgroundColor: Color {
        switch line.type {
        case .addition:
            return AppTheme.diffAdditionBg
        case .deletion:
            return AppTheme.diffDeletionBg
        case .context:
            return .clear
        }
    }

    private var prefixColor: Color {
        switch line.type {
        case .addition:
            return AppTheme.diffAdditionText
        case .deletion:
            return AppTheme.diffDeletionText
        case .context:
            return AppTheme.diffContextText
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Line number gutter
            if let lineNum = line.lineNumber {
                Text("\(lineNum)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 32, alignment: .trailing)
                    .padding(.trailing, AppTheme.spacingXS)
            }

            // Prefix (+/-/space)
            Text(line.type.rawValue)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 14)

            // Content
            Text(line.content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, AppTheme.spacingXS)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }
}

// MARK: - Previews

#Preview("Code Diff") {
    ScrollView {
        CodeDiffView(
            diff: .constant(CodeDiff(
                filename: "Views/Chat/Components/MCQQuestionView.swift",
                language: "swift",
                hunks: [
                    CodeDiff.DiffHunk(
                        header: "@@ -0,0 +1,25 @@",
                        lines: [
                            CodeDiff.DiffLine(content: "import SwiftUI", type: .addition, lineNumber: 1),
                            CodeDiff.DiffLine(content: "", type: .addition, lineNumber: 2),
                            CodeDiff.DiffLine(content: "struct MCQQuestionView: View {", type: .addition, lineNumber: 3),
                            CodeDiff.DiffLine(content: "    let question: MCQQuestion", type: .addition, lineNumber: 4),
                            CodeDiff.DiffLine(content: "    let onOptionSelected: (MCQOption) -> Void", type: .addition, lineNumber: 5),
                            CodeDiff.DiffLine(content: "", type: .addition, lineNumber: 6),
                            CodeDiff.DiffLine(content: "    var body: some View {", type: .addition, lineNumber: 7),
                            CodeDiff.DiffLine(content: "        VStack(alignment: .leading) {", type: .addition, lineNumber: 8),
                            CodeDiff.DiffLine(content: "            // Question content", type: .addition, lineNumber: 9),
                            CodeDiff.DiffLine(content: "        }", type: .addition, lineNumber: 10),
                            CodeDiff.DiffLine(content: "    }", type: .addition, lineNumber: 11),
                            CodeDiff.DiffLine(content: "}", type: .addition, lineNumber: 12),
                        ]
                    )
                ]
            ))
        )
    }
    .padding(.vertical)
    .background(AppTheme.backgroundPrimary)
}

#Preview("Mixed Diff") {
    ScrollView {
        CodeDiffView(
            diff: .constant(CodeDiff(
                filename: "Models/Message.swift",
                language: "swift",
                hunks: [
                    CodeDiff.DiffHunk(
                        header: "@@ -8,6 +8,8 @@",
                        lines: [
                            CodeDiff.DiffLine(content: "    let timestamp: Date", type: .context, lineNumber: 8),
                            CodeDiff.DiffLine(content: "    let codeBlocks: [CodeBlock]?", type: .context, lineNumber: 9),
                            CodeDiff.DiffLine(content: "    let isStreaming: Bool", type: .deletion, lineNumber: 10),
                            CodeDiff.DiffLine(content: "    var isStreaming: Bool", type: .addition, lineNumber: 10),
                            CodeDiff.DiffLine(content: "    var richContent: ChatContent?", type: .addition, lineNumber: 11),
                            CodeDiff.DiffLine(content: "", type: .context, lineNumber: 12),
                        ]
                    )
                ]
            ))
        )
    }
    .padding(.vertical)
    .background(AppTheme.backgroundPrimary)
}
