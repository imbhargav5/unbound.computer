//
//  TabComponents.swift
//  unbound-macos
//
//  Shadcn-styled tab components
//

import SwiftUI

// MARK: - Tab Bar

struct TabBar: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var tabs: [ChatTab]
    @Binding var selectedTabId: UUID?
    var onAddTab: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Tab items
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isSelected: selectedTabId == tab.id,
                            onSelect: { selectedTabId = tab.id },
                            onClose: { closeTab(tab) }
                        )
                    }
                }
            }

            // Add tab button
            Button(action: onAddTab) {
                Image(systemName: "plus")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(colors.mutedForeground)
                    .frame(width: Spacing.xxl, height: Spacing.xxl)
            }
            .buttonGhost(size: .icon)
            .padding(.horizontal, Spacing.xs)

            Spacer()
        }
        .background(colors.card)
    }

    private func closeTab(_ tab: ChatTab) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.remove(at: index)

            // Select another tab if the closed one was selected
            if selectedTabId == tab.id {
                if !tabs.isEmpty {
                    selectedTabId = tabs[max(0, index - 1)].id
                } else {
                    selectedTabId = nil
                }
            }
        }
    }
}

// MARK: - Tab Item View

struct TabItemView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tab: ChatTab
    let isSelected: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var isHovering = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: IconSize.xs))
                    .foregroundStyle(colors.mutedForeground)

                Text(tab.displayTitle)
                    .font(Typography.bodySmall)
                    .foregroundStyle(isSelected ? colors.foreground : colors.mutedForeground)
                    .lineLimit(1)

                if isHovering || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? colors.background : Color.clear)
            .overlay(
                Rectangle()
                    .frame(height: BorderWidth.thick)
                    .foregroundStyle(isSelected ? colors.primary : Color.clear),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Segmented Tab Picker

struct SegmentedTabPicker<T: Hashable & Identifiable & RawRepresentable>: View where T.RawValue == String {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selection: T
    let options: [T]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(option.rawValue)
                        .font(Typography.bodySmall)
                        .foregroundStyle(selection.id == option.id ? colors.foreground : colors.mutedForeground)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            selection.id == option.id ?
                            colors.card :
                            Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.xs)
        .background(colors.muted)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}
