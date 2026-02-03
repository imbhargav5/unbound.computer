//
//  mockup_watchosApp.swift
//  mockup-watchos Watch App
//
//  Created by Bhargav Ponnapalli on 02/02/26.
//

import SwiftUI
import UserNotifications

@main
struct UnboundWatchApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear {
                    setupNotifications()
                }
        }
    }

    private func setupNotifications() {
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
        }
    }
}
