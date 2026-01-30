import SwiftUI

@main
struct SessionsApp: App {
    @StateObject private var authService = AuthenticationService.shared

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environmentObject(authService)
        }
    }
}
