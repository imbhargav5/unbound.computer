//
//  ChatPerformanceSignposts.swift
//  unbound-macos
//
//  Lightweight OSLog signposts for chat performance tracing.
//  Compiled out in Release builds.
//

import Foundation

#if DEBUG
import OSLog
#endif

enum ChatPerformanceSignposts {
    struct IntervalToken {
        #if DEBUG
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        #endif
    }

    #if DEBUG
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.unbound.macos"
    private static let logger = Logger(subsystem: subsystem, category: "chat.performance")
    private static let signposter = OSSignposter(logger: logger)
    #endif

    static func beginInterval(_ name: StaticString, _ message: String = "") -> IntervalToken {
        #if DEBUG
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id, "\(message, privacy: .public)")
        return IntervalToken(name: name, state: state)
        #else
        return IntervalToken()
        #endif
    }

    static func endInterval(_ token: IntervalToken, _ message: String = "") {
        #if DEBUG
        signposter.endInterval(token.name, token.state, "\(message, privacy: .public)")
        #endif
    }

    static func event(_ name: StaticString, _ message: String = "") {
        #if DEBUG
        signposter.emitEvent(name, "\(message, privacy: .public)")
        #endif
    }
}
