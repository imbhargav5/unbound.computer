//
//  SettingsView.swift
//  unbound-macos
//
//  Settings view with custom sidebar and content area
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
        HStack(spacing: 0) {
            SettingsSidebar(selectedSection: $selectedSection)

            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(colors.background)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .general:
            GeneralSettings()
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
            PrivacySettings()
        }
    }
}

#if DEBUG

#Preview {
    SettingsView()
        .environment(AppState())
        .frame(width: 900, height: 600)
}

#endif
