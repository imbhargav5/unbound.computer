//
//  MockData.swift
//  mockup-watchos Watch App
//

import Foundation

enum WatchMockData {
    // MARK: - Devices

    static let devices: [WatchDevice] = [
        WatchDevice(
            id: "device-1",
            name: "Bhargav's MacBook Pro",
            type: .macbookPro,
            status: .online,
            activeSessionCount: 2
        ),
        WatchDevice(
            id: "device-2",
            name: "Office Mac Studio",
            type: .macStudio,
            status: .online,
            activeSessionCount: 1
        ),
        WatchDevice(
            id: "device-3",
            name: "Home Mac Mini",
            type: .macMini,
            status: .offline,
            activeSessionCount: 0
        ),
        WatchDevice(
            id: "device-4",
            name: "Dev Linux Server",
            type: .linux,
            status: .busy,
            activeSessionCount: 3
        )
    ]

    // MARK: - Sessions

    static let sessions: [WatchSession] = [
        WatchSession(
            id: "session-1",
            projectName: "auth-feature",
            deviceName: "MacBook Pro",
            deviceType: .macbookPro,
            status: .generating,
            startedAt: Date().addingTimeInterval(-154),
            pendingMCQ: nil
        ),
        WatchSession(
            id: "session-2",
            projectName: "fix-bug-123",
            deviceName: "Mac Studio",
            deviceType: .macStudio,
            status: .waitingInput,
            startedAt: Date().addingTimeInterval(-342),
            pendingMCQ: WatchMCQ(
                question: "Which test framework should I use?",
                options: ["Jest", "Vitest", "Mocha"],
                allowsCustomInput: true
            )
        ),
        WatchSession(
            id: "session-3",
            projectName: "refactor-api",
            deviceName: "MacBook Pro",
            deviceType: .macbookPro,
            status: .paused,
            startedAt: Date().addingTimeInterval(-890),
            pendingMCQ: nil
        ),
        WatchSession(
            id: "session-4",
            projectName: "update-deps",
            deviceName: "Linux Server",
            deviceType: .linux,
            status: .completed,
            startedAt: Date().addingTimeInterval(-1800),
            pendingMCQ: nil
        ),
        WatchSession(
            id: "session-5",
            projectName: "db-migration",
            deviceName: "Mac Studio",
            deviceType: .macStudio,
            status: .error,
            startedAt: Date().addingTimeInterval(-600),
            pendingMCQ: nil
        )
    ]

    // MARK: - Sample MCQs

    static let sampleMCQs: [WatchMCQ] = [
        WatchMCQ(
            question: "Which test framework should I use?",
            options: ["Jest", "Vitest", "Mocha"],
            allowsCustomInput: true
        ),
        WatchMCQ(
            question: "How should I handle authentication?",
            options: ["JWT", "Session-based", "OAuth"],
            allowsCustomInput: true
        ),
        WatchMCQ(
            question: "Create PR now?",
            options: ["Yes, create PR", "No, continue working"],
            allowsCustomInput: false
        ),
        WatchMCQ(
            question: "Apply these changes to files?",
            options: ["Yes, apply all", "Review first", "Cancel"],
            allowsCustomInput: false
        )
    ]

    // MARK: - Helpers

    static var activeSessions: [WatchSession] {
        sessions.filter { $0.status.isActive }
    }

    static var sessionCount: Int {
        sessions.count
    }

    static var activeSessionCount: Int {
        activeSessions.count
    }

    static var waitingInputCount: Int {
        sessions.filter { $0.status == .waitingInput }.count
    }
}
