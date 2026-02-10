import SwiftUI

struct DeviceSessionRowView: View {
    let session: SyncedSession

    var body: some View {
        HStack(spacing: AppTheme.spacingM) {
            Image(systemName: "archivebox")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(session.isActive ? AppTheme.amberAccent : AppTheme.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(Typography.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(session.lastAccessedAt.formatted(.relative(presentation: .named)))
                    .font(Typography.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, AppTheme.spacingM)
        .padding(.vertical, AppTheme.spacingS)
        .background(
            session.isActive
                ? AppTheme.amberAccent.opacity(0.06)
                : Color.clear
        )
        .overlay(
            Group {
                if session.isActive {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .stroke(AppTheme.amberAccent.opacity(0.3), lineWidth: AppTheme.thinBorderWidth)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }
}
