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
    case repositories = "Repositories"
    case appearance = "Appearance"
    case notifications = "Notifications"
    case privacy = "Privacy"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .repositories: return "folder"
        case .appearance: return "paintbrush"
        case .notifications: return "bell"
        case .privacy: return "lock.shield"
        }
    }
}
