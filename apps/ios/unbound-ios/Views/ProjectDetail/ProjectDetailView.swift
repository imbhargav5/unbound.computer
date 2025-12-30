import SwiftUI

struct ProjectDetailView: View {
    let device: Device
    let project: Project

    @Environment(\.navigationManager) private var navigationManager
    @State private var chats: [Chat] = []

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                    // Project Header
                    projectHeader

                    // Chats Section
                    if chats.isEmpty {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: "No Chats Yet",
                            message: "Start a new conversation with Claude to get help with this project.",
                            actionTitle: "New Chat"
                        ) {
                            navigationManager.navigateToNewChat(in: project)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                            Text("Recent Chats")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, AppTheme.spacingM)

                            LazyVStack(spacing: AppTheme.spacingM) {
                                ForEach(chats) { chat in
                                    ChatRowView(chat: chat)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                            impactFeedback.impactOccurred()
                                            navigationManager.navigateToChat(chat)
                                        }
                                }
                            }
                            .padding(.horizontal, AppTheme.spacingM)
                        }
                    }
                }
                .padding(.top, AppTheme.spacingM)
                .padding(.bottom, 100) // Space for FAB
            }
            .background(AppTheme.backgroundPrimary)

            // Floating Action Button
            if !chats.isEmpty {
                FloatingActionButton(icon: "plus") {
                    navigationManager.navigateToNewChat(in: project)
                }
                .padding(.trailing, AppTheme.spacingL)
                .padding(.bottom, AppTheme.spacingL)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            chats = MockData.chats(for: project)
        }
    }

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingM) {
            HStack(spacing: AppTheme.spacingM) {
                // Language Icon
                ZStack {
                    Circle()
                        .fill(project.language.color.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: project.language.iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(project.language.color)
                }

                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    HStack {
                        Text(project.language.rawValue)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)

                        if project.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow)
                        }
                    }

                    Text(project.path)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    if let description = project.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            // Device info
            HStack(spacing: AppTheme.spacingS) {
                Image(systemName: device.type.iconName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)

                Text(device.name)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
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
        .padding(.horizontal, AppTheme.spacingM)
    }
}

#Preview {
    NavigationStack {
        ProjectDetailView(
            device: MockData.devices[0],
            project: MockData.projects[0]
        )
    }
    .tint(AppTheme.accent)
}
