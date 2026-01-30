import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppTheme.spacingL) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.6))

            VStack(spacing: AppTheme.spacingS) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.spacingL)
                        .padding(.vertical, AppTheme.spacingS)
                        .background(AppTheme.accentGradient)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(AppTheme.spacingXL)
    }
}

#Preview {
    VStack(spacing: 40) {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: "No Chats Yet",
            message: "Start a new conversation with Claude to get help with your project."
        )

        EmptyStateView(
            icon: "laptopcomputer",
            title: "No Devices Found",
            message: "Connect to a device running Claude Code to get started.",
            actionTitle: "Scan for Devices"
        ) {
            logger.debug("Scanning...")
        }
    }
}
