//
//  ProjectsSettings.swift
//  unbound-macos
//
//  Manage registered projects
//

import SwiftUI

struct ProjectsSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var isAddingProject = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                // Header
                Text("Projects")
                    .font(Typography.h2)
                    .foregroundStyle(colors.foreground)

                Text("Manage your registered projects. Add git repositories to create workspaces from them.")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)

                ShadcnDivider()

                // Add project button
                HStack {
                    Button {
                        addProject()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "plus")
                                .font(.system(size: IconSize.sm))
                            Text("Add Project")
                                .font(Typography.bodySmall)
                        }
                    }
                    .buttonPrimary(size: .sm)
                    .disabled(isAddingProject)

                    if isAddingProject {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.leading, Spacing.sm)
                    }

                    Spacer()
                }

                // Projects list
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if appState.projectsService.projects.isEmpty {
                        EmptyProjectsView()
                    } else {
                        ForEach(appState.projectsService.recentProjects) { project in
                            ProjectRow(
                                project: project,
                                onRemove: {
                                    removeProject(project)
                                }
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding(Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.background)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    private func addProject() {
        isAddingProject = true

        Task {
            do {
                _ = try await appState.projectsService.addProjectWithPicker()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isAddingProject = false
        }
    }

    private func removeProject(_ project: Project) {
        do {
            try appState.projectsService.removeProject(project)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Empty Projects View

struct EmptyProjectsView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(colors.mutedForeground)

            Text("No projects registered")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Text("Add a git repository to get started with creating workspaces.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.muted.opacity(0.3))
                .stroke(colors.border, style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let project: Project
    var onRemove: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Folder icon
            Image(systemName: project.isGitRepository ? "folder.fill.badge.gearshape" : "folder.fill")
                .font(.system(size: IconSize.lg))
                .foregroundStyle(colors.primary)
                .frame(width: 32, height: 32)

            // Project info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(project.name)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(colors.foreground)

                Text(project.displayPath)
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
            }

            Spacer()

            // Last accessed
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("Last accessed")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Text(project.lastAccessed.formatted(.relative(presentation: .named)))
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
            }

            // Status indicator
            if !project.exists {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: IconSize.md))
                    .foregroundStyle(colors.warning)
                    .help("Project folder not found")
            }

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(colors.mutedForeground)
            }
            .buttonGhost(size: .icon)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(isHovered ? colors.accent : colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ProjectsSettings()
        .environment(AppState())
        .frame(width: 600, height: 500)
}
