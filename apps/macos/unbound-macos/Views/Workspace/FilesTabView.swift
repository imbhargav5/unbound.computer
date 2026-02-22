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
                            FilesTabRow(
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
            .padding(.vertical, 8)
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

// MARK: - Files Tab Row

private struct FilesTabRow: View {
    let item: FileItem
    let level: Int
    var viewModel: FileTreeViewModel?
    var onFileSelected: (FileItem) -> Void

    private var isExpanded: Bool {
        viewModel?.isExpanded(item.path) ?? false
    }

    private var isDimmed: Bool {
        item.name == "node_modules" || item.name == ".git"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.hasChildren {
                    let willExpand = !(viewModel?.isExpanded(item.path) ?? false)
                    viewModel?.toggleExpanded(item.path)
                    if willExpand && item.isDirectory && !item.childrenLoaded {
                        Task {
                            await viewModel?.loadChildren(for: item.path)
                        }
                    }
                } else if !item.isDirectory {
                    onFileSelected(item)
                }
            } label: {
                HStack(spacing: 6) {
                    // Chevron (folders) or spacer (files)
                    if item.hasChildren {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: "6B6B6B"))
                            .frame(width: 12, height: 12)
                    } else {
                        Color.clear
                            .frame(width: 12, height: 12)
                    }

                    // Folder/file icon
                    Image(systemName: item.isDirectory ? (isExpanded ? "folder.fill" : "folder") : "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(isDimmed ? Color(hex: "555555") : Color(hex: "6B6B6B"))
                        .frame(width: 14, height: 14)

                    // Name
                    Text(item.name)
                        .font(GeistFont.sans(size: 12, weight: .regular))
                        .foregroundStyle(isDimmed ? Color(hex: "555555") : Color(hex: "CCCCCC"))
                        .lineLimit(1)
                }
                .padding(.leading, 16 + CGFloat(level) * 16)
                .padding(.trailing, 16)
                .frame(height: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Children
            if isExpanded && item.hasChildren {
                ForEach(item.children) { child in
                    FilesTabRow(
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

#if DEBUG

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

#endif
