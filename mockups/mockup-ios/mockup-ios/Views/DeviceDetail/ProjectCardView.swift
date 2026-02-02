import SwiftUI

struct ProjectCardView: View {
    let project: Project
    let isCompact: Bool

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            // Language icon
            ZStack {
                Circle()
                    .fill(project.language.color.opacity(0.15))
                    .frame(width: isCompact ? 40 : 48, height: isCompact ? 40 : 48)

                Image(systemName: project.language.iconName)
                    .font(.system(size: isCompact ? 18 : 22, weight: .medium))
                    .foregroundStyle(project.language.color)
            }

            // Project name with favorite indicator
            HStack(spacing: AppTheme.spacingXS) {
                Text(project.name)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                if project.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }

            // Language badge
            Text(project.language.rawValue)
                .font(.caption2.weight(.medium))
                .foregroundStyle(project.language.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(project.language.color.opacity(0.15))
                .clipShape(Capsule())

            // Chat count
            Text("\(project.chatCount) chat\(project.chatCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
        .shadow(
            color: AppTheme.cardShadowColor,
            radius: AppTheme.cardShadowRadius,
            x: 0,
            y: AppTheme.cardShadowY
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
}

#Preview {
    LazyVGrid(columns: [
        GridItem(.flexible()),
        GridItem(.flexible())
    ], spacing: 16) {
        ForEach(MockData.projects) { project in
            ProjectCardView(project: project, isCompact: true)
        }
    }
    .padding()
    .background(Color(UIColor.systemBackground))
}
