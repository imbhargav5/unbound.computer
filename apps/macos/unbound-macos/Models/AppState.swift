//
//  AppState.swift
//  unbound-macos
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import SwiftUI

// MARK: - Theme Mode

enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - App State

@Observable
class AppState {
    // Theme
    var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode")
        }
    }

    // Navigation
    var showSettings: Bool = false

    // Selected workspace
    var selectedWorkspaceId: UUID?
    var selectedRepositoryId: UUID?

    // Services
    let shellService: ShellService
    let gitService: GitService
    let projectsService: ProjectsService
    let workspacesService: WorkspacesService
    let claudeService: ClaudeService
    let chatStorageService: ChatStorageService

    init() {
        // Load theme from UserDefaults
        if let savedTheme = UserDefaults.standard.string(forKey: "themeMode"),
           let theme = ThemeMode(rawValue: savedTheme) {
            self.themeMode = theme
        } else {
            self.themeMode = .system
        }

        // Initialize services
        shellService = ShellService()
        gitService = GitService(shell: shellService)
        projectsService = ProjectsService(gitService: gitService)
        workspacesService = WorkspacesService(gitService: gitService, projectsService: projectsService)
        claudeService = ClaudeService(shell: shellService)
        chatStorageService = ChatStorageService()

        // Load persisted data
        do {
            try projectsService.load()
            try workspacesService.load()
            try chatStorageService.load()
        } catch {
            print("Failed to load persisted data: \(error)")
        }
    }
}
