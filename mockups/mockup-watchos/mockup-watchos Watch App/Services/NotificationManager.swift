//
//  NotificationManager.swift
//  mockup-watchos Watch App
//

import Combine
import SwiftUI
import UserNotifications

// MARK: - Notification Categories

enum NotificationCategory: String {
    case mcqQuestion = "MCQ_QUESTION"
    case sessionComplete = "SESSION_COMPLETE"
    case sessionError = "SESSION_ERROR"
    case deviceOffline = "DEVICE_OFFLINE"
}

// MARK: - Notification Actions

enum NotificationAction: String {
    // MCQ actions
    case option1 = "OPTION_1"
    case option2 = "OPTION_2"
    case option3 = "OPTION_3"
    case openApp = "OPEN_APP"

    // Session actions
    case viewSession = "VIEW_SESSION"
    case dismiss = "DISMISS"
}

// MARK: - Notification Manager

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var pendingNotificationSessionId: String?

    private init() {}

    // MARK: - Setup

    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            if granted {
                await setupCategories()
            }
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    private func setupCategories() async {
        let center = UNUserNotificationCenter.current()

        // MCQ Question category with quick reply options
        let option1Action = UNNotificationAction(
            identifier: NotificationAction.option1.rawValue,
            title: "Option 1",
            options: []
        )
        let option2Action = UNNotificationAction(
            identifier: NotificationAction.option2.rawValue,
            title: "Option 2",
            options: []
        )
        let option3Action = UNNotificationAction(
            identifier: NotificationAction.option3.rawValue,
            title: "Option 3",
            options: []
        )
        let openAction = UNNotificationAction(
            identifier: NotificationAction.openApp.rawValue,
            title: "Open App",
            options: .foreground
        )

        let mcqCategory = UNNotificationCategory(
            identifier: NotificationCategory.mcqQuestion.rawValue,
            actions: [option1Action, option2Action, option3Action, openAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Session complete category
        let viewAction = UNNotificationAction(
            identifier: NotificationAction.viewSession.rawValue,
            title: "View",
            options: .foreground
        )
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss.rawValue,
            title: "Dismiss",
            options: .destructive
        )

        let completeCategory = UNNotificationCategory(
            identifier: NotificationCategory.sessionComplete.rawValue,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Error category
        let errorCategory = UNNotificationCategory(
            identifier: NotificationCategory.sessionError.rawValue,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([mcqCategory, completeCategory, errorCategory])
    }

    // MARK: - Send Notifications

    func sendMCQNotification(sessionId: String, question: String, options: [String]) {
        let content = UNMutableNotificationContent()
        content.title = "Claude asking..."
        content.body = question
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.mcqQuestion.rawValue
        content.userInfo = [
            "sessionId": sessionId,
            "options": options
        ]
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "mcq-\(sessionId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendSessionCompleteNotification(sessionId: String, projectName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Session Complete"
        content.body = "\(projectName) has finished"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.sessionComplete.rawValue
        content.userInfo = ["sessionId": sessionId]

        let request = UNNotificationRequest(
            identifier: "complete-\(sessionId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendSessionErrorNotification(sessionId: String, projectName: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Session Error"
        content.body = "\(projectName): \(error)"
        content.sound = .defaultCritical
        content.categoryIdentifier = NotificationCategory.sessionError.rawValue
        content.userInfo = ["sessionId": sessionId]
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "error-\(sessionId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Handle Notification Response

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        let sessionId = userInfo["sessionId"] as? String

        switch response.actionIdentifier {
        case NotificationAction.option1.rawValue,
             NotificationAction.option2.rawValue,
             NotificationAction.option3.rawValue:
            // Handle MCQ quick reply
            if let options = userInfo["options"] as? [String] {
                let index: Int
                switch response.actionIdentifier {
                case NotificationAction.option1.rawValue: index = 0
                case NotificationAction.option2.rawValue: index = 1
                case NotificationAction.option3.rawValue: index = 2
                default: index = 0
                }

                if index < options.count {
                    HapticManager.mcqAnswered()
                    print("MCQ answered for session \(sessionId ?? "unknown"): \(options[index])")
                }
            }

        case NotificationAction.openApp.rawValue,
             NotificationAction.viewSession.rawValue,
             UNNotificationDefaultActionIdentifier:
            // Open app to session
            pendingNotificationSessionId = sessionId

        default:
            break
        }
    }
}
