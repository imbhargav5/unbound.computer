//
//  WorkspacesSidebar.swift
//  unbound-macos
//
//  Shadcn-styled workspaces sidebar
//

import SwiftUI

struct WorkspacesSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @Binding var workspaces: [Workspace]
    @Binding var selectedWorkspace: Workspace?
    var onOpenSettings: () -> Void
    var onAddProject: () -> Void
    var onCreateWorkspaceForProject: (Project) -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Group workspaces by their parent project
    private var workspacesByProject: [(project: Project, workspaces: [Workspace])] {
        let projects = appState.projectsService.projects
        return projects.compactMap { project in
            let projectWorkspaces = workspaces.filter { $0.projectId == project.id }
            guard !projectWorkspaces.isEmpty else { return nil }
            return (project: project, workspaces: projectWorkspaces)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Projects header
            SidebarHeader(title: "Projects") {
                // Menu action
            }
            .padding(.top, Spacing.sm)

            ShadcnDivider()
                .padding(.horizontal, Spacing.md)

            // Workspaces list grouped by project or empty state
            if workspacesByProject.isEmpty {
                ProjectsEmptyState(onAddRepository: onAddProject)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(workspacesByProject, id: \.project.id) { group in
                            ProjectGroup(
                                project: group.project,
                                workspaces: group.workspaces,
                                selectedWorkspace: $selectedWorkspace,
                                onCreateWorkspace: onCreateWorkspaceForProject
                            )
                        }
                    }
                    .padding(.top, Spacing.sm)
                    .padding(.horizontal, Spacing.sm)
                }
            }

            ShadcnDivider()

            // Footer
            SidebarFooter(
                onAddRepository: onAddProject,
                onOpenSettings: onOpenSettings
            )
        }
        .background(colors.background)
    }
}

// MARK: - Project Group

struct ProjectGroup: View {
    @Environment(\.colorScheme) private var colorScheme

    let project: Project
    let workspaces: [Workspace]
    @Binding var selectedWorkspace: Workspace?
    var onCreateWorkspace: (Project) -> Void

    @State private var isExpanded: Bool = true
    @State private var isHoveringAdd: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header
            Button {
                withAnimation(.easeInOut(duration: Duration.fast)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: IconSize.xs, weight: .semibold))
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: IconSize.sm)

                    Image(systemName: "folder.fill")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(colors.info)

                    Text(project.name)
                        .font(Typography.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.foreground)

                    Spacer()

                    Text("\(workspaces.count)")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Workspaces under this project
            if isExpanded {
                // Create workspace button (at top)
                Button {
                    onCreateWorkspace(project)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(colors.mutedForeground)

                        Text("New workspace")
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .padding(.leading, Spacing.xl)
                    .padding(.trailing, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(isHoveringAdd ? colors.muted : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isHoveringAdd = hovering
                    }
                }

                ForEach(workspaces) { workspace in
                    WorkspaceRowInGroup(
                        workspace: workspace,
                        isSelected: selectedWorkspace?.id == workspace.id,
                        onSelect: {
                            selectedWorkspace = workspace
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Workspace Row In Group (simplified, no binding needed)

struct WorkspaceRowInGroup: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    let workspace: Workspace
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var gitStatus: GitStatus?
    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Branch icon
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(colors.mutedForeground)

                // Workspace name and branch
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)

                    if let branch = gitStatus?.branch {
                        Text(branch)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                    }
                }

                Spacer()

                // Clean/dirty indicator
                if let status = gitStatus {
                    Circle()
                        .fill(status.isClean ? colors.success : colors.warning)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.leading, Spacing.xl)  // Indent under project
            .padding(.trailing, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
        .task {
            await loadGitStatus()
        }
    }

    private func loadGitStatus() async {
        guard let path = workspace.worktreePath else { return }

        do {
            gitStatus = try await appState.gitService.status(at: path)
        } catch {
            gitStatus = nil
        }
    }
}

// MARK: - Workspace Row

struct WorkspaceRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @Binding var workspace: Workspace
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var gitStatus: GitStatus?
    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Branch icon
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(colors.mutedForeground)

                // Workspace name and branch
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(Typography.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.foreground)

                    if let branch = gitStatus?.branch {
                        Text(branch)
                            .font(Typography.caption)
                            .foregroundStyle(colors.mutedForeground)
                    }
                }

                Spacer()

                // Clean/dirty indicator
                if let status = gitStatus {
                    Circle()
                        .fill(status.isClean ? colors.success : colors.warning)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
        .task {
            await loadGitStatus()
        }
    }

    private func loadGitStatus() async {
        guard let path = workspace.worktreePath else { return }

        do {
            gitStatus = try await appState.gitService.status(at: path)
        } catch {
            gitStatus = nil
        }
    }
}

#Preview {
    WorkspacesSidebar(
        workspaces: .constant(FakeData.workspaces),
        selectedWorkspace: .constant(nil),
        onOpenSettings: {},
        onAddProject: {},
        onCreateWorkspaceForProject: { _ in }
    )
    .environment(AppState())
    .frame(width: 280, height: 600)
}
