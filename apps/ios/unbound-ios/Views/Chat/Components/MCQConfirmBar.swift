import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct MCQConfirmBar: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: AppTheme.spacingM) {
                // Cancel button
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, AppTheme.spacingM)
                        .padding(.vertical, AppTheme.spacingS)
                }

                Spacer()

                // Confirm button
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onConfirm()
                } label: {
                    HStack(spacing: AppTheme.spacingXS) {
                        Text("Confirm")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.spacingL)
                    .padding(.vertical, AppTheme.spacingS)
                    .background(AppTheme.accentGradient)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, AppTheme.spacingS)
            .background(.ultraThinMaterial)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        MCQConfirmBar(
            onConfirm: { logger.debug("Confirmed") },
            onCancel: { logger.debug("Cancelled") }
        )
    }
}
