//
//  unbound_iosApp.swift
//  unbound-ios
//
//  Created by Bhargav Ponnapalli on 27/12/25.
//

import SwiftUI

@main
struct unbound_iosApp: App {
    @State private var navigationManager = NavigationManager()

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
