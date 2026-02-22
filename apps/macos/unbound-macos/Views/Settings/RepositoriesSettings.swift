//
//  RepositoriesSettings.swift
//  unbound-macos
//
//  Manage registered repositories
//

import SwiftUI

struct RepositoriesSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var isAddingRepository = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var navigationPath = NavigationPath()

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            SettingsPageContainer(title: "Repositories", subtitle: "Manage your registered repositories.") {
                HStack {
                    Button {
                        addRepository()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "plus")
                                .font(.system(size: IconSize.sm))
                            Text("Add Repository")
                                .font(Typography.bodySmall)
                        }
                    }
                    .buttonPrimary(size: .sm)
                    .disabled(isAddingRepository)

                    if isAddingRepository {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.leading, Spacing.sm)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    if appState.repositories.isEmpty {
                        EmptyRepositoriesSettingsView()
                    } else {
                        ForEach(appState.repositories) { repository in
                            RepositoryRow(
                                repository: repository,
                                onSelect: {
                                    navigationPath.append(repository)
                                },
                                onRemove: {
                                    removeRepository(repository)
                                }
                            )
                        }
                    }
                }
            }
            .navigationDestination(for: Repository.self) { repository in
                RepositorySettingsView(repository: repository, navigationPath: $navigationPath)
                    .environment(appState)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    private func addRepository() {
        isAddingRepository = true

        Task {
            do {
                // Show folder picker
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = false
                panel.message = "Select a repository folder"
                panel.prompt = "Add Repository"

                let response = await panel.begin()
                if response == .OK, let url = panel.url {
                    _ = try await appState.addRepository(path: url.path)
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isAddingRepository = false
        }
    }

    private func removeRepository(_ repository: Repository) {
        Task {
            do {
                try await appState.removeRepository(repository.id)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Empty Repositories Settings View

struct EmptyRepositoriesSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(colors.mutedForeground)

            Text("No repositories registered")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Text("Add a git repository to get started with creating sessions.")
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

// MARK: - Repository Row

struct RepositoryRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
    var onSelect: () -> Void
    var onRemove: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                // Folder icon
                Image(systemName: repository.isGitRepository ? "folder.fill.badge.gearshape" : "folder.fill")
                    .font(.system(size: IconSize.lg))
                    .foregroundStyle(colors.primary)
                    .frame(width: 32, height: 32)

                // Repository info
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(repository.name)
                        .font(Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.foreground)

                    Text(repository.displayPath)
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }

                Spacer()

                // Last accessed
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("Last accessed")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)

                    Text(repository.lastAccessed.formatted(.relative(presentation: .named)))
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }

                // Status indicator
                if !repository.exists {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: IconSize.md))
                        .foregroundStyle(colors.warning)
                        .help("Repository folder not found")
                }

                // Settings chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: IconSize.sm, weight: .semibold))
                    .foregroundStyle(colors.mutedForeground)
                    .opacity(isHovered ? 1 : 0.5)

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }
}

#if DEBUG

#Preview {
    RepositoriesSettings()
        .environment(AppState())
        .frame(width: 600, height: 500)
}

#endif
