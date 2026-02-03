//
//  WatchSession.swift
//  mockup-watchos Watch App
//

import SwiftUI

struct WatchSession: Identifiable, Hashable {
    let id: String
    let projectName: String
    let deviceName: String
    let deviceType: WatchDeviceType
    var status: WatchSessionStatus
    let startedAt: Date
    var pendingMCQ: WatchMCQ?

    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    var elapsedTimeFormatted: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum WatchSessionStatus: String, CaseIterable {
    case generating
    case paused
    case waitingInput
    case completed
    case error

    var icon: String {
        switch self {
        case .generating: return "sparkles"
        case .paused: return "pause.circle.fill"
        case .waitingInput: return "questionmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .generating: return .green
        case .paused: return .yellow
        case .waitingInput: return .orange
        case .completed: return .blue
        case .error: return .red
        }
    }

    var label: String {
        switch self {
        case .generating: return "Generating"
        case .paused: return "Paused"
        case .waitingInput: return "Needs Input"
        case .completed: return "Completed"
        case .error: return "Error"
        }
    }

    var shortLabel: String {
        switch self {
        case .generating: return "Gen..."
        case .paused: return "Paused"
        case .waitingInput: return "Input"
        case .completed: return "Done"
        case .error: return "Error"
        }
    }

    var isActive: Bool {
        switch self {
        case .generating, .paused, .waitingInput:
            return true
        case .completed, .error:
            return false
        }
    }

    var canPause: Bool {
        self == .generating
    }

    var canResume: Bool {
        self == .paused
    }

    var canStop: Bool {
        switch self {
        case .generating, .paused, .waitingInput:
            return true
        case .completed, .error:
            return false
        }
    }
}
