//
//  SettingsView.swift
//  unbound-macos
//
//  Shadcn-styled settings view
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSection: SettingsSection = .appearance

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            SettingsSidebar(selectedSection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // Content
            settingsContent
                .frame(maxWidth: 600, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.showSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: IconSize.sm, weight: .semibold))
                        .foregroundStyle(colors.mutedForeground)
                }
                .buttonGhost(size: .icon)
            }
        }
        .background(colors.background)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .general:
            PlaceholderSettings(section: .general)
        case .account:
            AccountSettings()
        case .repositories:
            RepositoriesSettings()
        case .network:
            NetworkSettings()
        case .appearance:
            AppearanceSettings()
        case .notifications:
            PlaceholderSettings(section: .notifications)
        case .privacy:
            PlaceholderSettings(section: .privacy)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .frame(width: 700, height: 500)
}
