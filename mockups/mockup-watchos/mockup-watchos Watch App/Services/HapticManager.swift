//
//  HapticManager.swift
//  mockup-watchos Watch App
//

import WatchKit

enum HapticManager {
    /// Play haptic for session status changes
    static func sessionStatusChanged(_ status: WatchSessionStatus) {
        switch status {
        case .generating:
            WKInterfaceDevice.current().play(.start)
        case .paused:
            WKInterfaceDevice.current().play(.click)
        case .waitingInput:
            WKInterfaceDevice.current().play(.notification)
        case .completed:
            WKInterfaceDevice.current().play(.success)
        case .error:
            WKInterfaceDevice.current().play(.failure)
        }
    }

    /// Play haptic for MCQ received
    static func mcqReceived() {
        WKInterfaceDevice.current().play(.notification)
    }

    /// Play haptic for MCQ answered
    static func mcqAnswered() {
        WKInterfaceDevice.current().play(.success)
    }

    /// Play haptic for button tap
    static func buttonTap() {
        WKInterfaceDevice.current().play(.click)
    }

    /// Play haptic for action confirmation
    static func actionConfirmed() {
        WKInterfaceDevice.current().play(.success)
    }

    /// Play haptic for action cancelled/failed
    static func actionFailed() {
        WKInterfaceDevice.current().play(.failure)
    }

    /// Play haptic for navigation
    static func navigate() {
        WKInterfaceDevice.current().play(.directionUp)
    }

    /// Play subtle haptic for selection
    static func selection() {
        WKInterfaceDevice.current().play(.click)
    }
}
