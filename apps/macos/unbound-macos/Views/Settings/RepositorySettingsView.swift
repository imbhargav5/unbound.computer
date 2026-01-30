//
//  RepositorySettingsView.swift
//  unbound-macos
//
//  Repository settings detail view for configuring session defaults
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct RepositorySettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
    @Binding var navigationPath: NavigationPath

    // Local state for editable fields
    @State private var sessionsPath: String = ""
    @State private var selectedBranch: String = ""
    @State private var selectedRemote: String = ""

    // Loading states
    @State private var branches: [String] = []
    @State private var remotes: [(name: String, url: String)] = []
    @State private var isLoadingBranches = false
    @State private var isLoadingRemotes = false

    // UI state
    @State private var showRemoveConfirmation = false
    @State private var isSaving = false
    @State private var hasChanges = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                headerSection
                ShadcnDivider()
                repositoryPathSection
                sessionsPathSection
                branchingSection
                remoteSection
                ShadcnDivider()
                dangerZoneSection
                Spacer()
            }
            .padding(Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.background)
        .navigationTitle(repository.name)
        .task {
            await loadInitialData()
        }
        .onChange(of: sessionsPath) { _, _ in hasChanges = true }
        .onChange(of: selectedBranch) { _, _ in hasChanges = true }
        .onChange(of: selectedRemote) { _, _ in hasChanges = true }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSettings()
                }
                .buttonPrimary(size: .sm)
                .disabled(!hasChanges || isSaving)
            }
        }
        .confirmationDialog(
            "Remove Repository?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                removeRepository()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \"\(repository.name)\" from Unbound. The repository files will not be deleted.")
        }
    }

    // MARK: - View Sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: IconSize.xl))
                    .foregroundStyle(colors.primary)

                Text(repository.name)
                    .font(Typography.h2)
                    .foregroundStyle(colors.foreground)
            }

            Text("Configure how sessions are created from this repository")
                .font(Typography.body)
                .foregroundStyle(colors.mutedForeground)
        }
    }

    @ViewBuilder
    private var repositoryPathSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Repository Path")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Root path")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                HStack {
                    Text(repository.displayPath)
                        .font(Typography.code)
                        .foregroundStyle(colors.foreground)

                    Spacer()

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repository.path)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: IconSize.sm))
                    }
                    .buttonGhost(size: .icon)
                    .help("Reveal in Finder")
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(colors.muted.opacity(0.5))
                )
            }
        }
    }

    @ViewBuilder
    private var sessionsPathSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Sessions")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Sessions path")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Text("Where worktrees for new sessions will be created")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground.opacity(0.7))

                HStack {
                    TextField("~/unbound/sessions/\(repository.name)", text: $sessionsPath)
                        .textFieldStyle(.plain)
                        .font(Typography.code)
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(colors.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .stroke(colors.border, lineWidth: BorderWidth.default)
                                )
                        )

                    Button {
                        selectSessionsPath()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: IconSize.sm))
                    }
                    .buttonGhost(size: .icon)
                    .help("Choose folder")
                }
            }
        }
    }

    @ViewBuilder
    private var branchingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Branching")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Branch new sessions from")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Text("The base branch for creating new session worktrees")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground.opacity(0.7))

                branchPicker
            }
        }
    }

    @ViewBuilder
    private var branchPicker: some View {
        if isLoadingBranches {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading branches...")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
            }
            .padding(Spacing.md)
        } else {
            Picker("", selection: $selectedBranch) {
                Text("Select branch").tag("")
                ForEach(branches, id: \.self) { branch in
                    Text(branch).tag(branch)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Remote")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Default remote")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Text("The remote to use for push/pull operations")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground.opacity(0.7))

                remotePicker
            }
        }
    }

    @ViewBuilder
    private var remotePicker: some View {
        if isLoadingRemotes {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading remotes...")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
            }
            .padding(Spacing.md)
        } else if remotes.isEmpty {
            Text("No remotes configured")
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
                .padding(Spacing.md)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Picker("", selection: $selectedRemote) {
                    Text("Select remote").tag("")
                    ForEach(remotes, id: \.name) { remote in
                        Text(remote.name).tag(remote.name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                if let selectedRemoteInfo = remotes.first(where: { $0.name == selectedRemote }) {
                    Text(selectedRemoteInfo.url)
                        .font(Typography.micro)
                        .foregroundStyle(colors.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Danger Zone")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Remove this repository from Unbound. This will not delete the actual files.")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "trash")
                            .font(.system(size: IconSize.sm))
                        Text("Remove Repository")
                    }
                }
                .buttonDestructive(size: .md)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(colors.destructive.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(colors.destructive.opacity(0.2), lineWidth: BorderWidth.default)
                    )
            )
        }
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        // Initialize with current values
        sessionsPath = repository.sessionsPath ?? ""
        selectedBranch = repository.defaultBranch ?? ""
        selectedRemote = repository.defaultRemote ?? ""

        // TODO: Load branches and remotes from daemon git.status/git.list_branches
        // For now, just mark loading as complete
        isLoadingBranches = false
        isLoadingRemotes = false

        // Reset changes flag after initial load
        hasChanges = false
    }

    // MARK: - Actions

    private func selectSessionsPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose where to create session worktrees"

        if panel.runModal() == .OK, let url = panel.url {
            sessionsPath = url.path
        }
    }

    private func saveSettings() {
        // TODO: Implement repository settings update via daemon
        isSaving = true
        hasChanges = false
        isSaving = false
    }

    private func removeRepository() {
        Task {
            do {
                // Use daemon to remove repository
                try await appState.removeRepository(repository.id)
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            } catch {
                logger.error("Failed to remove repository: \(error)")
            }
        }
    }
}

#Preview {
    @Previewable @State var navigationPath = NavigationPath()
    RepositorySettingsView(
        repository: Repository(
            path: "/Users/dev/projects/unbound.computer",
            name: "unbound.computer"
        ),
        navigationPath: $navigationPath
    )
    .environment(AppState())
}
