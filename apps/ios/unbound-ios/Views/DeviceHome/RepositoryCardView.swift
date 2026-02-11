import SwiftUI

struct RepositoryCardView: View {
    let repository: SyncedRepository
    let sessions: [SyncedSession]
    @Binding var isExpanded: Bool
    let onSessionTap: (SyncedSession) -> Void
    var onCreateSession: (() -> Void)?

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
                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.horizontal, AppTheme.spacingM)

                if sessions.isEmpty {
                    Text("No sessions")
                        .font(Typography.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, AppTheme.spacingM)
                        .padding(.vertical, AppTheme.spacingS)
                } else {
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

                if let onCreateSession {
                    Button {
                        onCreateSession()
                    } label: {
                        HStack(spacing: AppTheme.spacingXS) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("New Session")
                                .font(Typography.caption)
                        }
                        .foregroundStyle(AppTheme.amberAccent)
                        .padding(.horizontal, AppTheme.spacingM)
                        .padding(.bottom, AppTheme.spacingS)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .thinBorderCard()
    }
}
