//
//  SettingsSidebar.swift
//  rocketry-macos
//
//  Shadcn-styled settings sidebar
//

import SwiftUI

struct SettingsSidebar: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedSection: SettingsSection

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        List(SettingsSection.allCases, selection: $selectedSection) { section in
            SettingsSidebarRow(
                section: section,
                isSelected: selectedSection == section
            )
            .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .background(colors.background)
    }
}

// MARK: - Settings Sidebar Row

struct SettingsSidebarRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let section: SettingsSection
    let isSelected: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Label {
            Text(section.rawValue)
                .font(Typography.bodySmall)
                .foregroundStyle(colors.foreground)
        } icon: {
            Image(systemName: section.iconName)
                .font(.system(size: IconSize.md))
                .foregroundStyle(isSelected ? colors.primary : colors.mutedForeground)
        }
    }
}

#Preview {
    SettingsSidebar(selectedSection: .constant(.appearance))
        .frame(width: 200, height: 400)
}
