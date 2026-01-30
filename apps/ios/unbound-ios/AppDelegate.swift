//
//  AppDelegate.swift
//  unbound-ios
//
//  UIApplicationDelegate for handling push notification registration callbacks.
//  Attached to SwiftUI app using @UIApplicationDelegateAdaptor.
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set the notification center delegate
        UNUserNotificationCenter.current().delegate = PushNotificationService.shared
        return true
    }

    // MARK: - Push Notification Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationService.shared.didRegisterForRemoteNotifications(with: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationService.shared.didFailToRegisterForRemoteNotifications(with: error)
    }

    // MARK: - Background Notifications

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle silent push notifications for Live Activity updates
        handleBackgroundNotification(userInfo: userInfo, completionHandler: completionHandler)
    }

    private func handleBackgroundNotification(
        userInfo: [AnyHashable: Any],
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let notificationType = userInfo["type"] as? String else {
            completionHandler(.noData)
            return
        }

        switch notificationType {
        case "live_activity_update":
            // Live Activity updates are handled by ActivityKit automatically
            // This is for any additional data syncing if needed
            completionHandler(.newData)

        case "session_sync":
            // Sync session data in the background
            Task {
                // TODO: Sync session data
                completionHandler(.newData)
            }

        default:
            completionHandler(.noData)
        }
    }
}
