//
//  mockup_iosApp.swift
//  mockup-ios
//
//  iOS UI Mockup for Unbound - for rapid prototyping and visualization

import SwiftUI

@main
struct mockup_iosApp: App {
    @State private var navigationManager = NavigationManager()

    init() {
        // Register Geist fonts on app startup
        FontRegistration.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigationManager.path) {
                DeviceListView()
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .deviceDetail(let device):
                            DeviceDetailView(device: device)
                        case .projectDetail(let device, let project):
                            ProjectDetailView(device: device, project: project)
                        case .chat(let chat):
                            ChatView(chat: chat)
                        case .newChat(let project):
                            ChatView(chat: nil, project: project)
                        case .accountSettings:
                            AccountSettingsView()
                        }
                    }
            }
            .environment(\.navigationManager, navigationManager)
            .tint(AppTheme.accent)
        }
    }
}
