import SwiftUI

struct ProjectCardView: View {
    let project: Project
    let isCompact: Bool

    @State private var isPressed = false

    init(project: Project, isCompact: Bool = true) {
        self.project = project
        self.isCompact = isCompact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
            // Header with language icon and favorite
            HStack {
                ZStack {
                    Circle()
                        .fill(project.language.color.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: project.language.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(project.language.color)
                }

                Spacer()

                if project.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.yellow)
                }
            }

            Spacer()

            // Project name
            Text(project.name)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            // Path
            Text(project.path)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)

            // Chat count badge
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 10))
                Text("\(project.chatCount) chat\(project.chatCount == 1 ? "" : "s")")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .background(AppTheme.accent.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(AppTheme.spacingM)
        .frame(height: isCompact ? 160 : 180)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            project.language.color.opacity(0.3),
                            project.language.color.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: AppTheme.cardShadowColor,
            radius: AppTheme.cardShadowRadius,
            x: 0,
            y: 4
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }

    func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }
}

#Preview("Project Cards") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
        ForEach(PreviewData.projects) { project in
            ProjectCardView(project: project)
        }
    }
    .padding()
    .background(AppTheme.backgroundPrimary)
}
