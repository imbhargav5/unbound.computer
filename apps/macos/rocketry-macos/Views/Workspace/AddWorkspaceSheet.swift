//
//  AddWorkspaceSheet.swift
//  rocketry-macos
//
//  Sheet for creating a new workspace from a registered project
//

import SwiftUI

struct AddWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var selectedProject: Project?
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Workspace")
                    .font(Typography.h3)
                    .foregroundStyle(colors.foreground)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: IconSize.sm, weight: .medium))
                        .foregroundStyle(colors.mutedForeground)
                }
                .buttonGhost(size: .icon)
            }
            .padding(Spacing.lg)

            ShadcnDivider()

            // Content
            if appState.projectsService.projects.isEmpty {
                // No projects registered
                EmptyProjectsPrompt(onOpenSettings: {
                    dismiss()
                    appState.showSettings = true
                })
                .padding(Spacing.lg)
            } else {
                // Project selection
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Select a project")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)

                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(appState.projectsService.recentProjects) { project in
                                ProjectSelectionRow(
                                    project: project,
                                    isSelected: selectedProject?.id == project.id,
                                    onSelect: {
                                        withAnimation(.easeInOut(duration: Duration.fast)) {
                                            selectedProject = project
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 300)

                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(colors.destructive)
                            Text(error)
                                .font(Typography.bodySmall)
                                .foregroundStyle(colors.destructive)
                        }
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(colors.destructive.opacity(0.1))
                        )
                    }
                }
                .padding(Spacing.lg)
            }

            Spacer()

            ShadcnDivider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonGhost(size: .md)

                Spacer()

                Button {
                    createWorkspace()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(isCreating ? "Creating..." : "Create Workspace")
                    }
                }
                .buttonPrimary(size: .md)
                .disabled(selectedProject == nil || isCreating)
            }
            .padding(Spacing.lg)
        }
        .frame(width: 450, height: 500)
        .background(colors.background)
    }

    private func createWorkspace() {
        guard let project = selectedProject else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                // Create workspace with worktree immediately
                let workspace = try await appState.workspacesService.createWorkspace(from: project)
                await MainActor.run {
                    appState.selectedWorkspaceId = workspace.id
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

// MARK: - Empty Projects Prompt

struct EmptyProjectsPrompt: View {
    @Environment(\.colorScheme) private var colorScheme
    var onOpenSettings: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(colors.mutedForeground)

            Text("No projects registered")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Text("Register a git repository first to create workspaces from it.")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                onOpenSettings()
            }
            .buttonPrimary(size: .md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Project Selection Row

struct ProjectSelectionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let project: Project
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? colors.primary : colors.border, lineWidth: BorderWidth.default)
                        .frame(width: 18, height: 18)

                    if isSelected {
                        Circle()
                            .fill(colors.primary)
                            .frame(width: 10, height: 10)
                    }
                }

                // Folder icon
                Image(systemName: "folder.fill")
                    .font(.system(size: IconSize.lg))
                    .foregroundStyle(colors.primary)

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

                // Workspace count
                let count = 0 // TODO: Get actual count from service
                if count > 0 {
                    Text("\(count) workspace\(count > 1 ? "s" : "")")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : colors.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(isSelected ? colors.primary : colors.border, lineWidth: isSelected ? BorderWidth.thick : BorderWidth.default)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    AddWorkspaceSheet()
        .environment(AppState())
}
