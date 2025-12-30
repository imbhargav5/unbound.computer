import SwiftUI

struct ActiveSession: Identifiable, Hashable {
    let id: UUID
    let projectName: String
    let chatTitle: String
    let deviceName: String
    var status: SessionStatus
    var progress: Double  // 0.0 - 1.0 for generating
    let startedAt: Date
    let language: Project.ProjectLanguage

    enum SessionStatus: String, CaseIterable {
        case generating
        case reviewing
        case ready
        case prReady
        case merged
        case failed

        var icon: String {
            switch self {
            case .generating: return "wand.and.stars"
            case .reviewing: return "eye"
            case .ready: return "checkmark.circle"
            case .prReady: return "arrow.triangle.pull"
            case .merged: return "arrow.triangle.merge"
            case .failed: return "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .generating: return AppTheme.accent
            case .reviewing: return .blue
            case .ready: return .green
            case .prReady: return .purple
            case .merged: return .green
            case .failed: return .red
            }
        }

        var label: String {
            switch self {
            case .generating: return "Generating..."
            case .reviewing: return "Reviewing"
            case .ready: return "Ready"
            case .prReady: return "PR Ready"
            case .merged: return "Merged"
            case .failed: return "Failed"
            }
        }

        var isActive: Bool {
            switch self {
            case .generating, .reviewing:
                return true
            default:
                return false
            }
        }
    }
}
