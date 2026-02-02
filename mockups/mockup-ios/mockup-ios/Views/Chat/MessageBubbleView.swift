import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppTheme.spacingS) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                ClaudeAvatarView(size: 28)
                    .padding(.bottom, 4)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: AppTheme.spacingXS) {
                // Message content
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(isUser ? .white : AppTheme.textPrimary)
                    .padding(.horizontal, AppTheme.spacingM)
                    .padding(.vertical, AppTheme.spacingS + 2)
                    .background(
                        isUser
                            ? AnyShapeStyle(AppTheme.accentGradient)
                            : AnyShapeStyle(AppTheme.assistantBubble)
                    )
                    .clipShape(MessageBubbleShape(isUser: isUser))

                // Code blocks if present
                if let codeBlocks = message.codeBlocks {
                    ForEach(codeBlocks) { block in
                        CodeBlockView(codeBlock: block)
                    }
                }

                // Timestamp
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, AppTheme.spacingM)
    }
}

// MARK: - Message Bubble Shape

struct MessageBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let smallRadius: CGFloat = 4

        var path = Path()

        if isUser {
            // User bubble - rounded on all corners except bottom-right
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - smallRadius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - smallRadius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        } else {
            // Assistant bubble - rounded on all corners except bottom-left
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + smallRadius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - smallRadius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let codeBlock: Message.CodeBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let filename = codeBlock.filename {
                    Text(filename)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(codeBlock.language)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = codeBlock.code
                    let impactFeedback = UINotificationFeedbackGenerator()
                    impactFeedback.notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .background(Color.black.opacity(0.3))

            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(AppTheme.spacingS)
            }
        }
        .background(Color(white: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .frame(maxWidth: 320)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(MockData.messages) { message in
                MessageBubbleView(message: message)
            }
        }
        .padding(.vertical)
    }
    .background(Color(UIColor.systemBackground))
}
