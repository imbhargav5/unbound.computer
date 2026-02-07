//
//  FilesTabView.swift
//  unbound-macos
//
//  Files tab showing the full file tree of the repository.
//

import SwiftUI

struct FilesTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    var fileTreeViewModel: FileTreeViewModel?
    var onFileSelected: (FileItem) -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let viewModel = fileTreeViewModel {
                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.allFilesTree.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(viewModel.allFilesTree) { item in
                            FilesTreeRow(
                                item: item,
                                level: 0,
                                viewModel: viewModel,
                                onFileSelected: onFileSelected
                            )
                        }
                    }
                } else {
                    emptyStateView
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Loading files...")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "folder")
                .font(.system(size: IconSize.xxxl))
                .foregroundStyle(colors.mutedForeground)

            Text("No files")
                .font(Typography.body)
                .foregroundStyle(colors.foreground)

            Text("Select a repository to view files")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Files Tree Row

struct FilesTreeRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: FileItem
    let level: Int
    var viewModel: FileTreeViewModel?
    var onFileSelected: (FileItem) -> Void

    @State private var isHovered: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var isSelected: Bool {
        viewModel?.selectedFilePath == item.path
    }

    private var isExpanded: Bool {
        viewModel?.isExpanded(item.path) ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.hasChildren {
                    let willExpand = !(viewModel?.isExpanded(item.path) ?? false)
                    withAnimation(.easeInOut(duration: Duration.default)) {
                        viewModel?.toggleExpanded(item.path)
                    }
                    if willExpand && item.isDirectory && !item.childrenLoaded {
                        Task {
                            await viewModel?.loadChildren(for: item.path)
                        }
                    }
                } else if !item.isDirectory {
                    onFileSelected(item)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    // Chevron for folders
                    if item.hasChildren {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.xs)
                    } else {
                        Color.clear
                            .frame(width: IconSize.xs)
                    }

                    // File/folder icon
                    Image(systemName: item.type.iconName)
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(item.type.iconColor(colors))

                    // Name
                    Text(item.name)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    Spacer()

                    // Git status indicator
                    if item.gitStatus != .unchanged {
                        Text(item.gitStatus.indicator)
                            .font(Typography.micro)
                            .foregroundStyle(item.gitStatus.color(colors))
                            .padding(.trailing, Spacing.xs)
                    }
                }
                .padding(.leading, CGFloat(level) * Spacing.lg + Spacing.md)
                .padding(.trailing, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
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

            // Children
            if isExpanded && item.hasChildren {
                ForEach(item.children) { child in
                    FilesTreeRow(
                        item: child,
                        level: level + 1,
                        viewModel: viewModel,
                        onFileSelected: onFileSelected
                    )
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("With Files") {
    FilesTabView(
        fileTreeViewModel: .preview(),
        onFileSelected: { _ in }
    )
    .frame(width: 280, height: 400)
}

#Preview("Empty") {
    FilesTabView(
        fileTreeViewModel: nil,
        onFileSelected: { _ in }
    )
    .frame(width: 280, height: 400)
}
