//
//  AppNavigation.swift
//  unbound-macos
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import SwiftUI

// MARK: - App Screen

enum AppScreen: Hashable {
    case dashboard
    case inbox
    case workspaces
    case agents
    case issues
    case approvals
    case projects
    case goals
    case activity
    case costs
    case settings

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .inbox: return "Inbox"
        case .workspaces: return "Workspaces"
        case .agents: return "Agents"
        case .issues: return "Issues"
        case .approvals: return "Approvals"
        case .projects: return "Projects"
        case .goals: return "Goals"
        case .activity: return "Activity"
        case .costs: return "Costs"
        case .settings: return "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .inbox: return "tray.full"
        case .workspaces: return "square.split.2x1"
        case .agents: return "person.2"
        case .issues: return "checklist"
        case .approvals: return "checkmark.seal"
        case .projects: return "shippingbox"
        case .goals: return "target"
        case .activity: return "waveform.path.ecg"
        case .costs: return "indianrupeesign.circle"
        case .settings: return "gearshape"
        }
    }
}

enum BoardShellKind: Hashable {
    case firstCompanySetup
    case companyDashboard
    case workspace
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
