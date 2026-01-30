//
//  MonotonicCounter.swift
//  unbound-macos
//
//  Thread-safe monotonically increasing counter using actor isolation.
//  Guarantees unique, sequential values across concurrent access.
//

import Foundation

/// Monotonically increasing counter with actor isolation for thread safety
actor MonotonicCounter {
    private var value: UInt64

    // MARK: - Initialization

    /// Initialize counter with starting value
    /// - Parameter startingAt: Initial counter value (default: 0)
    init(startingAt: UInt64 = 0) {
        self.value = startingAt
    }

    // MARK: - Counter Operations

    /// Get the next value (increments counter)
    /// - Returns: Next sequential value
    func next() -> UInt64 {
        value += 1
        return value
    }

    /// Get current value without incrementing
    /// - Returns: Current counter value
    func current() -> UInt64 {
        value
    }

    /// Reset counter to a specific value
    /// - Parameter newValue: Value to reset to
    func reset(to newValue: UInt64) {
        value = newValue
    }

    /// Increment by a specific amount
    /// - Parameter amount: Amount to increment by
    /// - Returns: New value after increment
    func increment(by amount: UInt64) -> UInt64 {
        value += amount
        return value
    }
}
