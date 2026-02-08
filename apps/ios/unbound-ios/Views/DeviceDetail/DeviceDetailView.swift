import SwiftUI

struct DeviceDetailView: View {
    let device: Device

    @Environment(\.navigationManager) private var navigationManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var projects: [Project] = []

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad or landscape - wider cards
            return [
                GridItem(.flexible(), spacing: AppTheme.spacingM),
                GridItem(.flexible(), spacing: AppTheme.spacingM),
                GridItem(.flexible(), spacing: AppTheme.spacingM)
            ]
        } else {
            // iPhone portrait - 2 column grid
            return [
                GridItem(.flexible(), spacing: AppTheme.spacingM),
                GridItem(.flexible(), spacing: AppTheme.spacingM)
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacingL) {
                // Device Header Card
                deviceHeader

                // Projects Section
                if projects.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "No Projects",
                        message: "This device has no projects with Claude Code sessions."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.spacingM) {
                        Text("Projects")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, AppTheme.spacingM)

                        LazyVGrid(columns: columns, spacing: AppTheme.spacingM) {
                            ForEach(projects) { project in
                                ProjectCardView(
                                    project: project,
                                    isCompact: horizontalSizeClass != .regular
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    navigationManager.navigateToProject(project, on: device)
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingM)
                    }
                }
            }
            .padding(.top, AppTheme.spacingM)
            .padding(.bottom, AppTheme.spacingXL)
        }
        .background(AppTheme.backgroundPrimary)
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            #if DEBUG
            projects = PreviewData.projects(for: device)
            #else
            // TODO: Load real projects from service
            projects = []
            #endif
        }
    }

    private var deviceHeader: some View {
        HStack(spacing: AppTheme.spacingM) {
            // Device Icon
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: device.type.iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text(device.type.rawValue)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(device.hostname)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: AppTheme.spacingM) {
                    DeviceStatusIndicator(status: device.status)

                    Text(device.osVersion)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Spacer()
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

#Preview("Device Detail") {
    NavigationStack {
        DeviceDetailView(device: PreviewData.devices[0])
    }
    .tint(AppTheme.accent)
}
