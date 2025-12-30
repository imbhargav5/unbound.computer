//
//  WorkspaceView.swift
//  unbound-macos
//
//  Shadcn-styled main workspace view
//

import SwiftUI

struct WorkspaceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var workspaces: [Workspace] = []
    @State private var selectedWorkspace: Workspace?

    // Chat state
    @State private var chatInput: String = ""
    @State private var selectedModel: AIModel = .defaultModel

    // Version control state
    @State private var fileTree: [FileItem] = []
    @State private var changesTree: [FileItem] = []
    @State private var selectedVCTab: VersionControlTab = .allFiles
    @State private var selectedTerminalTab: TerminalTab = .terminal

    // File system service
    private let fileSystemService = FileSystemService()

    // State
    @State private var isAddingProject = false
    @State private var hasMigratedOrphans = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HSplitView {
            // Left sidebar - Workspaces
            WorkspacesSidebar(
                workspaces: $workspaces,
                selectedWorkspace: $selectedWorkspace,
                onOpenSettings: {
                    appState.showSettings = true
                },
                onAddProject: {
                    addProject()
                },
                onCreateWorkspaceForProject: { project in
                    createWorkspace(for: project)
                }
            )
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)

            // Center - Chat Panel
            if let workspaceId = selectedWorkspace?.id {
                ChatPanel(
                    tabs: Binding(
                        get: { appState.chatStorageService.tabs(for: workspaceId) },
                        set: { appState.chatStorageService.setTabs($0, for: workspaceId) }
                    ),
                    selectedTabId: Binding(
                        get: { appState.chatStorageService.selectedTabId(for: workspaceId) },
                        set: { appState.chatStorageService.setSelectedTabId($0, for: workspaceId) }
                    ),
                    chatInput: $chatInput,
                    selectedModel: $selectedModel,
                    currentRepo: selectedWorkspace?.name ?? "workspace",
                    workspacePath: selectedWorkspace?.worktreePath
                )
                .id(workspaceId)  // Force view recreation when workspace changes
                .frame(minWidth: 400)
            } else {
                WorkspaceEmptyState(
                    hasProjects: !workspaces.isEmpty,
                    onAddRepository: { addProject() }
                )
                .frame(minWidth: 400)
            }

            // Right sidebar - Version Control
            VersionControlPanel(
                fileTree: selectedVCTab == .changes ? $changesTree : $fileTree,
                selectedTab: $selectedVCTab,
                selectedTerminalTab: $selectedTerminalTab,
                workingDirectory: selectedWorkspace?.worktreePath
            )
            .frame(minWidth: 200, idealWidth: 300, maxWidth: 500)
        }
        .background(colors.background)
        .task {
            loadWorkspaces()
            await migrateOrphanProjects()
        }
        .onChange(of: appState.workspacesService.workspaces) { _, _ in
            loadWorkspaces()
        }
        .onChange(of: selectedWorkspace?.id) { _, newWorkspaceId in
            // Initialize tabs for workspace if needed
            if let workspaceId = newWorkspaceId {
                appState.chatStorageService.initializeTabsIfNeeded(for: workspaceId)
            }
        }
        .task(id: selectedWorkspace?.worktreePath) {
            await loadFileTree()
        }
    }

    private func loadWorkspaces() {
        workspaces = appState.workspacesService.activeWorkspaces

        // Auto-select first workspace if none selected
        if selectedWorkspace == nil, let first = workspaces.first {
            selectedWorkspace = first
            appState.chatStorageService.initializeTabsIfNeeded(for: first.id)
        }

        // Update selected workspace if it was modified
        if let selected = selectedWorkspace,
           let updated = workspaces.first(where: { $0.id == selected.id }) {
            selectedWorkspace = updated
        }
    }

    private func loadFileTree() async {
        guard let path = selectedWorkspace?.worktreePath else {
            fileTree = []
            changesTree = []
            return
        }

        // Load all files
        fileTree = fileSystemService.scanDirectory(at: path)

        // Load changes from git status
        do {
            let status = try await appState.gitService.status(at: path)
            changesTree = fileSystemService.buildChangesTree(from: status)
        } catch {
            changesTree = []
        }
    }

    private func createWorkspace(for project: Project) {
        Task {
            do {
                let workspace = try await appState.workspacesService.createWorkspace(from: project)
                loadWorkspaces()
                selectedWorkspace = workspace
            } catch {
                print("Failed to create workspace: \(error)")
            }
        }
    }

    private func addProject() {
        guard !isAddingProject else { return }
        isAddingProject = true

        Task {
            do {
                if let project = try await appState.projectsService.addProjectWithPicker() {
                    // Auto-create a workspace for the new project
                    let workspace = try await appState.workspacesService.createWorkspace(from: project)
                    loadWorkspaces()
                    selectedWorkspace = workspace
                }
            } catch {
                print("Failed to add project: \(error)")
            }
            isAddingProject = false
        }
    }

    private func migrateOrphanProjects() async {
        guard !hasMigratedOrphans else { return }
        hasMigratedOrphans = true

        let allWorkspaces = appState.workspacesService.workspaces
        let projectsWithWorkspaces = Set(allWorkspaces.compactMap { $0.projectId })
        let orphanProjects = appState.projectsService.projects.filter {
            !projectsWithWorkspaces.contains($0.id)
        }

        for project in orphanProjects {
            do {
                _ = try await appState.workspacesService.createWorkspace(from: project)
            } catch {
                print("Failed to migrate orphan project \(project.name): \(error)")
            }
        }

        if !orphanProjects.isEmpty {
            loadWorkspaces()
        }
    }
}

#Preview {
    WorkspaceView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}
