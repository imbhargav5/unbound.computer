import SwiftUI

struct RepositoryCardView: View {
    let repository: SyncedRepository
    let sessions: [SyncedSession]
    @Binding var isExpanded: Bool
    let onSessionTap: (SyncedSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.spacingS) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.amberAccent)

                    Text(repository.name)
                        .font(Typography.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if !sessions.isEmpty {
                        Text("\(sessions.count)")
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                }
                .padding(AppTheme.spacingM)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                if sessions.isEmpty {
                    Text("No sessions")
                        .font(Typography.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, AppTheme.spacingM)
                        .padding(.bottom, AppTheme.spacingM)
                } else {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.horizontal, AppTheme.spacingM)

                    VStack(spacing: 4) {
                        ForEach(sessions) { session in
                            DeviceSessionRowView(session: session)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    onSessionTap(session)
                                }
                        }
                    }
                    .padding(.vertical, AppTheme.spacingXS)
                }
            }
        }
        .thinBorderCard()
    }
}
