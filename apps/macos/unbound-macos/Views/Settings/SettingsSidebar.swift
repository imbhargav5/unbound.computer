//
//  SettingsSidebar.swift
//  unbound-macos
//
//  Custom settings sidebar with back button and styled nav items
//

import SwiftUI

struct SettingsSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @Binding var selectedSection: SettingsSection

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Traffic light spacer
            Color.clear
                .frame(height: 28)
                .background(WindowDragView())

            // Back button
            Button {
                appState.showSettings = false
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: IconSize.lg))
                        .foregroundStyle(colors.primary)

                    Text("Back")
                        .font(GeistFont.sans(size: FontSize.smMd, weight: .medium))
                        .foregroundStyle(colors.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: LayoutMetrics.toolbarHeight)
                .padding(.horizontal, Spacing.xl)
            }
            .buttonStyle(.plain)

            // Nav list
            VStack(spacing: Spacing.xxs) {
                // Home item
                SettingsNavItem(
                    icon: "house",
                    label: "Home",
                    isSelected: false,
                    action: { appState.showSettings = false }
                )

                // Section items
                ForEach(SettingsSection.allCases) { section in
                    SettingsNavItem(
                        icon: section.iconName,
                        label: section.rawValue,
                        isSelected: selectedSection == section,
                        action: { selectedSection = section }
                    )
                }
            }
            .padding(Spacing.md)

            Spacer()
        }
        .frame(width: 260)
        .background(colors.card)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(colors.border)
                .frame(width: BorderWidth.default)
        }
    }
}

// MARK: - Settings Nav Item

struct SettingsNavItem: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? colors.primary : colors.sidebarMeta)

                Text(label)
                    .font(GeistFont.sans(size: FontSize.smMd, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? colors.primary : colors.mutedForeground)

                Spacer()
            }
            .frame(height: LayoutMetrics.compactToolbarHeight)
            .padding(.horizontal, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.xxl)
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
    }
}

#Preview {
    SettingsSidebar(selectedSection: .constant(.appearance))
        .frame(width: 260, height: 500)
        .environment(AppState())
}
