//
//  SiriShortcuts.swift
//  mockup-watchos Watch App
//

import AppIntents
import SwiftUI

// MARK: - Check Sessions Intent

struct CheckSessionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Claude Sessions"
    static var description = IntentDescription("Check the status of your active Claude Code sessions")

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let activeCount = WatchMockData.activeSessions.count
        let waitingCount = WatchMockData.waitingInputCount

        let message: String
        if activeCount == 0 {
            message = "You have no active Claude sessions."
        } else if waitingCount > 0 {
            message = "You have \(activeCount) active session\(activeCount == 1 ? "" : "s"). \(waitingCount) need\(waitingCount == 1 ? "s" : "") your input."
        } else {
            message = "You have \(activeCount) active session\(activeCount == 1 ? "" : "s") running."
        }

        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Pause All Sessions Intent

struct PauseAllSessionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause All Claude Sessions"
    static var description = IntentDescription("Pause all currently running Claude Code sessions")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let activeCount = WatchMockData.sessions.filter { $0.status == .generating }.count

        if activeCount == 0 {
            return .result(dialog: "No sessions are currently generating.")
        }

        // In production, this would send pause commands via relay
        HapticManager.actionConfirmed()

        return .result(dialog: "Paused \(activeCount) session\(activeCount == 1 ? "" : "s").")
    }
}

// MARK: - Resume All Sessions Intent

struct ResumeAllSessionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume All Claude Sessions"
    static var description = IntentDescription("Resume all paused Claude Code sessions")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pausedCount = WatchMockData.sessions.filter { $0.status == .paused }.count

        if pausedCount == 0 {
            return .result(dialog: "No sessions are currently paused.")
        }

        // In production, this would send resume commands via relay
        HapticManager.actionConfirmed()

        return .result(dialog: "Resumed \(pausedCount) session\(pausedCount == 1 ? "" : "s").")
    }
}

// MARK: - View Sessions Intent (opens app)

struct ViewSessionsIntent: AppIntent {
    static var title: LocalizedStringResource = "View Claude Sessions"
    static var description = IntentDescription("Open the app to view your Claude Code sessions")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct UnboundShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckSessionsIntent(),
            phrases: [
                "Check my \(.applicationName) sessions",
                "Check \(.applicationName) status",
                "How are my \(.applicationName) sessions"
            ],
            shortTitle: "Check Sessions",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: PauseAllSessionsIntent(),
            phrases: [
                "Pause all \(.applicationName) sessions",
                "Pause \(.applicationName)",
                "Stop \(.applicationName) sessions"
            ],
            shortTitle: "Pause All",
            systemImageName: "pause.circle.fill"
        )

        AppShortcut(
            intent: ResumeAllSessionsIntent(),
            phrases: [
                "Resume \(.applicationName) sessions",
                "Continue \(.applicationName) sessions",
                "Unpause \(.applicationName)"
            ],
            shortTitle: "Resume All",
            systemImageName: "play.circle.fill"
        )

        AppShortcut(
            intent: ViewSessionsIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName) sessions",
                "View \(.applicationName)"
            ],
            shortTitle: "View Sessions",
            systemImageName: "list.bullet"
        )
    }
}
