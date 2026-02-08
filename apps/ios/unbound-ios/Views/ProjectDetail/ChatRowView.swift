import SwiftUI

struct ChatRowView: View {
    let chat: Chat

    @State private var isPressed = false

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingM) {
            // Chat Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: chat.status.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            // Chat Info
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                HStack {
                    Text(chat.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Text(chat.preview)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: AppTheme.spacingS) {
                    Label("\(chat.messageCount)", systemImage: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)

                    if chat.status == .active {
                        Text("Active")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.statusOnline)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.statusOnline.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.top, 4)
        }
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
        .shadow(
            color: AppTheme.cardShadowColor,
            radius: AppTheme.cardShadowRadius,
            x: 0,
            y: AppTheme.cardShadowY
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }

    private var statusColor: Color {
        switch chat.status {
        case .active:
            return AppTheme.accent
        case .completed:
            return AppTheme.statusOnline
        case .archived:
            return AppTheme.textTertiary
        }
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: chat.lastMessageAt, relativeTo: Date())
    }
}

#Preview("Chat Rows") {
    VStack(spacing: 16) {
        ForEach(PreviewData.chats) { chat in
            ChatRowView(chat: chat)
        }
    }
    .padding()
    .background(AppTheme.backgroundPrimary)
}
