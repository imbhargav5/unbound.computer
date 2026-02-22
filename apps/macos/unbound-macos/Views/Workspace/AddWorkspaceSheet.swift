//
//  AddWorkspaceSheet.swift
//  unbound-macos
//
//  Sheet for creating a new session from a registered repository
//

import SwiftUI

struct AddWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var selectedRepository: Repository?
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Session")
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
            if appState.repositories.isEmpty {
                // No repositories registered
                EmptyRepositoriesPrompt(onOpenSettings: {
                    dismiss()
                    appState.showSettings = true
                })
                .padding(Spacing.lg)
            } else {
                // Repository selection
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Select a repository")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.mutedForeground)

                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(appState.repositories) { repository in
                                RepositorySelectionRow(
                                    repository: repository,
                                    isSelected: selectedRepository?.id == repository.id,
                                    onSelect: {
                                        withAnimation(.easeInOut(duration: Duration.fast)) {
                                            selectedRepository = repository
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
                    createSession()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(isCreating ? "Creating..." : "Create Session")
                    }
                }
                .buttonPrimary(size: .md)
                .disabled(selectedRepository == nil || isCreating)
            }
            .padding(Spacing.lg)
        }
        .frame(width: 450, height: 500)
        .background(colors.background)
    }

    private func createSession() {
        guard let repository = selectedRepository else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                // Create session for the repository via daemon
                let session = try await appState.createSession(
                    repositoryId: repository.id,
                    title: "New conversation"
                )
                await MainActor.run {
                    appState.selectSession(session.id)
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

// MARK: - Empty Repositories Prompt

struct EmptyRepositoriesPrompt: View {
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

            Text("No repositories registered")
                .font(Typography.h4)
                .foregroundStyle(colors.foreground)

            Text("Register a git repository first to create sessions from it.")
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

// MARK: - Repository Selection Row

struct RepositorySelectionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let repository: Repository
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

                // Session count
                let count = 0 // TODO: Get actual count from service
                if count > 0 {
                    Text("\(count) session\(count > 1 ? "s" : "")")
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

#if DEBUG

#Preview {
    AddWorkspaceSheet()
        .environment(AppState())
}

#endif
