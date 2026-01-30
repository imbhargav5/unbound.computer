import Foundation

enum Config {
    static let supabaseURL = ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "https://your-project.supabase.co"
    static let supabaseAnonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? ""
    static let relayWebSocketURL = ProcessInfo.processInfo.environment["RELAY_WS_URL"] ?? "wss://relay.unbound.computer"
    static let apiURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://api.unbound.computer"

    #if DEBUG
    static let enableLogging = true
    #else
    static let enableLogging = false
    #endif

    static func log(_ message: String) {
        if enableLogging {
            print("📱 [SessionsApp] \(message)")
        }
    }
}
