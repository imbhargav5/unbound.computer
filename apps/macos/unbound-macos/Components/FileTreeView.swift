//
//  FileTreeView.swift
//  unbound-macos
//
//  Shadcn-styled file tree view
//

import SwiftUI

// MARK: - File Tree View

struct FileTreeView: View {
    @Binding var items: [FileItem]
    var onSelect: ((FileItem) -> Void)?

    var body: some View {
        List {
            ForEach($items) { $item in
                FileTreeRow(item: $item, level: 0, onSelect: onSelect)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - File Tree Row

struct FileTreeRow: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var item: FileItem
    let level: Int
    var onSelect: ((FileItem) -> Void)?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.hasChildren {
                    withAnimation(.easeInOut(duration: Duration.default)) {
                        item.isExpanded.toggle()
                    }
                } else {
                    onSelect?(item)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    // Expand/collapse indicator for folders
                    if item.hasChildren {
                        Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
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
                }
                .padding(.leading, CGFloat(level) * Spacing.md)
                .padding(.vertical, Spacing.xs)
                .padding(.horizontal, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()

            // Children
            if item.isExpanded && item.hasChildren {
                ForEach($item.children) { $child in
                    FileTreeRow(item: $child, level: level + 1, onSelect: onSelect)
                }
            }
        }
    }
}

// MARK: - Simple File List (non-expandable)

struct SimpleFileList: View {
    let items: [FileItem]
    var onSelect: ((FileItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                SimpleFileRow(item: item, onSelect: onSelect)
            }
        }
    }
}

// MARK: - Simple File Row

struct SimpleFileRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: FileItem
    var onSelect: ((FileItem) -> Void)?

    @State private var isHovering = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button {
            onSelect?(item)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: item.type.iconName)
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(item.type.iconColor(colors))

                Text(item.name)
                    .font(Typography.bodySmall)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isHovering ? colors.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
