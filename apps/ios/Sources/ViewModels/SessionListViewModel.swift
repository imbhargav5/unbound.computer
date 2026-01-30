import Foundation
import SwiftUI

/// ViewModel for displaying the list of coding sessions
/// Migrated to @Observable for iOS 17+ (from ObservableObject + @Published)
@MainActor
@Observable
final class SessionListViewModel {
    var sessions: [CodingSession] = []
    var isLoading = false
    var error: Error?

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
    }

    func loadSessions() async {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            sessions = try await supabaseService.fetchSessions()
        } catch {
            self.error = error
            Config.log("❌ Failed to load sessions: \(error)")
        }
    }

    func refreshSessions() async {
        await loadSessions()
    }

    // Filter sessions by status
    func filterSessions(by status: SessionStatus) -> [CodingSession] {
        sessions.filter { $0.status == status }
    }

    // Get sessions grouped by date
    func groupedSessions() -> [(Date, [CodingSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.createdAt)
        }

        return grouped.sorted { $0.key > $1.key }
    }
}
