import Logging
import SwiftUI

private let logger = Logger(label: "app.ui.chat")

struct ChatInputView: View {
    @Binding var text: String
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: AppTheme.spacingS) {
                // Text field
                TextField("Message Claude...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, AppTheme.spacingM)
                    .padding(.vertical, AppTheme.spacingS + 2)
                    .background(AppTheme.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
                    .focused($isFocused)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend {
                            sendMessage()
                        }
                    }

                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            canSend ? AppTheme.accent : AppTheme.textTertiary
                        )
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.2), value: canSend)
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, AppTheme.spacingS)
            .background(.ultraThinMaterial)
        }
    }

    private func sendMessage() {
        guard canSend else { return }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        onSend()
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var text = ""

        var body: some View {
            VStack {
                Spacer()
                ChatInputView(text: $text) {
                    logger.debug("Send: \(text)")
                    text = ""
                }
            }
        }
    }

    return PreviewWrapper()
}
