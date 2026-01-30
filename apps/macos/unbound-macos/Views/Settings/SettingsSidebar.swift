//
//  SettingsSidebar.swift
//  unbound-macos
//
//  Shadcn-styled settings sidebar
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
        List {
            // Home button to navigate back to dashboard
            Button {
                appState.showSettings = false
            } label: {
                Label {
                    Text("Home")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .fixedSize(horizontal: true, vertical: false)
                } icon: {
                    Image(systemName: "house")
                        .font(.system(size: IconSize.md))
                        .foregroundStyle(colors.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Settings sections
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    section: section,
                    isSelected: selectedSection == section
                )
                .tag(section)
                .onTapGesture {
                    selectedSection = section
                }
            }
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
                .fixedSize(horizontal: true, vertical: false)
        } icon: {
            Image(systemName: section.iconName)
                .font(.system(size: IconSize.md))
                .foregroundStyle(isSelected ? colors.primary : colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsSidebar(selectedSection: .constant(.appearance))
        .frame(width: 200, height: 400)
}
