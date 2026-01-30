//
//  AppNavigation.swift
//  unbound-macos
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import SwiftUI

// MARK: - App Screen

enum AppScreen: Hashable {
    case workspace
    case settings
}

// MARK: - Settings Section

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case account = "Account"
    case repositories = "Repositories"
    case network = "Network"
    case appearance = "Appearance"
    case notifications = "Notifications"
    case privacy = "Privacy"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .account: return "person.circle"
        case .repositories: return "folder"
        case .network: return "network"
        case .appearance: return "paintbrush"
        case .notifications: return "bell"
        case .privacy: return "lock.shield"
        }
    }
}
