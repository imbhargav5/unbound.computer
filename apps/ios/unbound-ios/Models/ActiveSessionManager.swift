import SwiftUI

@Observable
class ActiveSessionManager {
    var sessions: [ActiveSession] = []
    var isSimulating = false

    private var simulationTask: Task<Void, Never>?

    var activeCount: Int {
        sessions.filter { $0.status.isActive }.count
    }

    var hasActiveSessions: Bool {
        !sessions.isEmpty
    }

    func startSimulation() {
        guard !isSimulating else { return }
        isSimulating = true

        // Initialize with mock sessions
        sessions = [
            ActiveSession(
                id: UUID(),
                projectName: "unbound-ios",
                chatTitle: "Implement device list view",
                deviceName: "MacBook Pro",
                status: .generating,
                progress: 0.0,
                startedAt: Date(),
                language: .swift
            ),
            ActiveSession(
                id: UUID(),
                projectName: "claude-code",
                chatTitle: "Fix navigation stack issues",
                deviceName: "MacBook Pro",
                status: .prReady,
                progress: 1.0,
                startedAt: Date().addingTimeInterval(-300),
                language: .typescript
            ),
            ActiveSession(
                id: UUID(),
                projectName: "ml-pipeline",
                chatTitle: "Add data validation",
                deviceName: "Mac Mini",
                status: .merged,
                progress: 1.0,
                startedAt: Date().addingTimeInterval(-600),
                language: .python
            ),
            ActiveSession(
                id: UUID(),
                projectName: "web-dashboard",
                chatTitle: "Update auth flow",
                deviceName: "MacBook Pro",
                status: .reviewing,
                progress: 0.0,
                startedAt: Date().addingTimeInterval(-120),
                language: .javascript
            ),
            ActiveSession(
                id: UUID(),
                projectName: "rust-server",
                chatTitle: "Optimize database queries",
                deviceName: "Linux Server",
                status: .failed,
                progress: 0.0,
                startedAt: Date().addingTimeInterval(-900),
                language: .rust
            )
        ]

        // Start Live Activity
        LiveActivityManager.shared.startLiveActivity(sessions: sessions)

        // Start progress simulation
        simulationTask = Task {
            await simulateProgress()
        }
    }

    func stopSimulation() {
        isSimulating = false
        simulationTask?.cancel()
        simulationTask = nil

        // End Live Activity
        LiveActivityManager.shared.endLiveActivity()

        sessions = []
    }

    private func simulateProgress() async {
        var updateCounter = 0

        while isSimulating && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))

            await MainActor.run {
                // Update progress for generating sessions
                for index in sessions.indices {
                    if sessions[index].status == .generating {
                        sessions[index].progress += 0.01
                        if sessions[index].progress >= 1.0 {
                            sessions[index].progress = 1.0
                            // Transition to next status
                            let nextStatuses: [ActiveSession.SessionStatus] = [.reviewing, .ready, .prReady]
                            sessions[index].status = nextStatuses.randomElement() ?? .ready
                        }
                    }
                }

                // Update Live Activity every 10 ticks (~1 second)
                updateCounter += 1
                if updateCounter >= 10 {
                    updateCounter = 0
                    LiveActivityManager.shared.updateLiveActivity(sessions: sessions)
                }
            }
        }
    }
}

// Environment key for the session manager
private struct ActiveSessionManagerKey: EnvironmentKey {
    static let defaultValue = ActiveSessionManager()
}

extension EnvironmentValues {
    var sessionManager: ActiveSessionManager {
        get { self[ActiveSessionManagerKey.self] }
        set { self[ActiveSessionManagerKey.self] = newValue }
    }
}
