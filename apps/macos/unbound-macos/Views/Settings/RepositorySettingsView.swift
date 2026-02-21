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
    @State private var worktreeRootDir: String = ""
    @State private var preCreateCommand: String = ""
    @State private var preCreateTimeoutSeconds: String = "300"
    @State private var postCreateCommand: String = ""
    @State private var postCreateTimeoutSeconds: String = "300"

    // Loading states
    @State private var branches: [String] = []
    @State private var remotes: [(name: String, url: String)] = []
    @State private var isLoadingBranches = false
    @State private var isLoadingRemotes = false

    // UI state
    @State private var showRemoveConfirmation = false
    @State private var isSaving = false
    @State private var hasChanges = false
    @State private var settingsError: String?
    @State private var isApplyingLoadedSettings = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var defaultWorktreeRootDir: String {
        "~/\(Config.baseDirName)/\(repository.id.uuidString.lowercased())/worktrees"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                headerSection
                if let settingsError {
                    Text(settingsError)
                        .font(Typography.caption)
                        .foregroundStyle(colors.destructive)
                }
                ShadcnDivider()
                repositoryPathSection
                sessionsPathSection
                worktreeRootSection
                branchingSection
                remoteSection
                setupHooksSection
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
        .onChange(of: sessionsPath) { _, _ in markChanged() }
        .onChange(of: selectedBranch) { _, _ in markChanged() }
        .onChange(of: selectedRemote) { _, _ in markChanged() }
        .onChange(of: worktreeRootDir) { _, _ in markChanged() }
        .onChange(of: preCreateCommand) { _, _ in markChanged() }
        .onChange(of: preCreateTimeoutSeconds) { _, _ in markChanged() }
        .onChange(of: postCreateCommand) { _, _ in markChanged() }
        .onChange(of: postCreateTimeoutSeconds) { _, _ in markChanged() }
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
            Button("Remove") {
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
            Text("Repository Metadata")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Sessions path (metadata only)")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Text("Optional repository metadata value. Worktree location is controlled below.")
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
    private var worktreeRootSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Worktree Location")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Worktree root directory")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)

                Text("Default: \(defaultWorktreeRootDir)")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground.opacity(0.7))

                HStack {
                    TextField(defaultWorktreeRootDir, text: $worktreeRootDir)
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
                        selectWorktreeRootDir()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: IconSize.sm))
                    }
                    .buttonGhost(size: .icon)
                    .help("Choose folder")

                    Button("Reset") {
                        worktreeRootDir = defaultWorktreeRootDir
                    }
                    .buttonGhost(size: .sm)
                    .help("Reset to daemon default")
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
    private var setupHooksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Setup Hooks")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Text("Commands run for worktree sessions. Failures stop session creation.")
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)

            hookEditor(
                title: "Pre-create hook",
                description: "Runs in the repository root before creating the worktree.",
                command: $preCreateCommand,
                timeoutSeconds: $preCreateTimeoutSeconds
            )

            hookEditor(
                title: "Post-create hook",
                description: "Runs in the created worktree after creation succeeds.",
                command: $postCreateCommand,
                timeoutSeconds: $postCreateTimeoutSeconds
            )
        }
    }

    @ViewBuilder
    private func hookEditor(
        title: String,
        description: String,
        command: Binding<String>,
        timeoutSeconds: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
            Text(description)
                .font(Typography.micro)
                .foregroundStyle(colors.mutedForeground.opacity(0.75))

            TextField("Command (optional, /bin/zsh -lc)", text: command)
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

            HStack(spacing: Spacing.sm) {
                Text("Timeout (seconds)")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                TextField("300", text: timeoutSeconds)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(colors.muted.opacity(0.25))
        )
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

                Button {
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
        apply(repositorySettings: RepositorySettings(
            repository: repository,
            worktreeRootDir: defaultWorktreeRootDir,
            worktreeDefaultBaseBranch: repository.defaultBranch,
            preCreateCommand: nil,
            preCreateTimeoutSeconds: 300,
            postCreateCommand: nil,
            postCreateTimeoutSeconds: 300
        ))

        do {
            let settings = try await appState.getRepositorySettings(repository.id)
            apply(repositorySettings: settings)
            settingsError = nil
        } catch {
            settingsError = "Failed to load repository settings: \(error.localizedDescription)"
            logger.error("Failed to load repository settings: \(error)")
        }

        // TODO: Load branches and remotes from daemon git.status/git.list_branches
        // For now, just mark loading as complete
        isLoadingBranches = false
        isLoadingRemotes = false
    }

    // MARK: - Actions

    private func selectSessionsPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Optional repository sessions metadata path"

        if panel.runModal() == .OK, let url = panel.url {
            sessionsPath = url.path
        }
    }

    private func selectWorktreeRootDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose default worktree root directory"

        if panel.runModal() == .OK, let url = panel.url {
            worktreeRootDir = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    private func saveSettings() {
        guard let preTimeout = parseTimeout(preCreateTimeoutSeconds),
              let postTimeout = parseTimeout(postCreateTimeoutSeconds) else {
            settingsError = "Hook timeout must be a positive integer."
            return
        }

        let sessionsPathValue = normalizedOptionalValue(sessionsPath)
        let branchValue = normalizedOptionalValue(selectedBranch)
        let remoteValue = normalizedOptionalValue(selectedRemote)
        let worktreeRootValue = normalizedOptionalValue(worktreeRootDir) ?? defaultWorktreeRootDir
        let preCommand = normalizedOptionalValue(preCreateCommand)
        let postCommand = normalizedOptionalValue(postCreateCommand)

        isSaving = true
        settingsError = nil

        Task {
            do {
                let updated = try await appState.updateRepositorySettings(
                    repository.id,
                    sessionsPath: sessionsPathValue,
                    defaultBranch: branchValue,
                    defaultRemote: remoteValue,
                    worktreeRootDir: worktreeRootValue,
                    worktreeDefaultBaseBranch: branchValue,
                    preCreateCommand: preCommand,
                    preCreateTimeoutSeconds: preTimeout,
                    postCreateCommand: postCommand,
                    postCreateTimeoutSeconds: postTimeout
                )
                apply(repositorySettings: updated)
                settingsError = nil
            } catch {
                settingsError = "Failed to save settings: \(error.localizedDescription)"
                logger.error("Failed to save repository settings: \(error)")
            }
            isSaving = false
        }
    }

    private func markChanged() {
        if isApplyingLoadedSettings {
            return
        }
        hasChanges = true
    }

    private func apply(repositorySettings: RepositorySettings) {
        isApplyingLoadedSettings = true
        sessionsPath = repositorySettings.repository.sessionsPath ?? ""
        selectedBranch =
            repositorySettings.repository.defaultBranch
            ?? repositorySettings.worktreeDefaultBaseBranch
            ?? ""
        selectedRemote = repositorySettings.repository.defaultRemote ?? ""
        worktreeRootDir = repositorySettings.worktreeRootDir.isEmpty
            ? defaultWorktreeRootDir
            : repositorySettings.worktreeRootDir
        preCreateCommand = repositorySettings.preCreateCommand ?? ""
        preCreateTimeoutSeconds = String(repositorySettings.preCreateTimeoutSeconds)
        postCreateCommand = repositorySettings.postCreateCommand ?? ""
        postCreateTimeoutSeconds = String(repositorySettings.postCreateTimeoutSeconds)
        hasChanges = false
        isApplyingLoadedSettings = false
    }

    private func normalizedOptionalValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseTimeout(_ value: String) -> Int? {
        guard let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsed > 0 else {
            return nil
        }
        return parsed
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
