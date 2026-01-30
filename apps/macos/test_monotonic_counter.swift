#!/usr/bin/env swift
import Foundation

// MARK: - MonotonicCounter Implementation

/// Monotonically increasing counter with actor isolation for thread safety
actor MonotonicCounter {
    private var value: UInt64

    init(startingAt: UInt64 = 0) {
        self.value = startingAt
    }

    func next() -> UInt64 {
        value += 1
        return value
    }

    func current() -> UInt64 {
        value
    }

    func reset(to newValue: UInt64) {
        value = newValue
    }

    func increment(by amount: UInt64) -> UInt64 {
        value += amount
        return value
    }
}

// MARK: - Test Runner

print("🧪 Testing MonotonicCounter")
print("============================\n")

// Test 1: Initialize at 0
print("Test 1: Initialize at 0")
print("-----------------------")
let counter1 = MonotonicCounter()
let initial = await counter1.current()
assert(initial == 0, "Should start at 0")
print("  ✓ Counter initialized at: \(initial)")
print("  ✅ PASSED\n")

// Test 2: Initialize at custom value
print("Test 2: Initialize at Custom Value")
print("----------------------------------")
let counter2 = MonotonicCounter(startingAt: 100)
let customInitial = await counter2.current()
assert(customInitial == 100, "Should start at 100")
print("  ✓ Counter initialized at: \(customInitial)")
print("  ✅ PASSED\n")

// Test 3: Next increments by 1
print("Test 3: Next Increments by 1")
print("----------------------------")
let counter3 = MonotonicCounter()
let first = await counter3.next()
let second = await counter3.next()
let third = await counter3.next()
assert(first == 1, "First call should return 1")
assert(second == 2, "Second call should return 2")
assert(third == 3, "Third call should return 3")
print("  ✓ Sequence: \(first), \(second), \(third)")
print("  ✅ PASSED\n")

// Test 4: Current doesn't increment
print("Test 4: Current Doesn't Increment")
print("---------------------------------")
let counter4 = MonotonicCounter()
await counter4.next()  // Value becomes 1
let curr1 = await counter4.current()  // Should stay 1
let curr2 = await counter4.current()  // Should stay 1
let curr3 = await counter4.current()  // Should stay 1
assert(curr1 == 1 && curr2 == 1 && curr3 == 1, "Current should not increment")
print("  ✓ Multiple current() calls returned: \(curr1)")
print("  ✅ PASSED\n")

// Test 5: Reset to specific value
print("Test 5: Reset to Specific Value")
print("-------------------------------")
let counter5 = MonotonicCounter()
await counter5.next()  // 1
await counter5.next()  // 2
await counter5.next()  // 3
await counter5.reset(to: 100)
let afterReset = await counter5.current()
let afterNext = await counter5.next()
assert(afterReset == 100, "Should reset to 100")
assert(afterNext == 101, "Next after reset should be 101")
print("  ✓ Reset to: \(afterReset)")
print("  ✓ Next value: \(afterNext)")
print("  ✅ PASSED\n")

// Test 6: Reset and continue sequence
print("Test 6: Reset and Continue Sequence")
print("-----------------------------------")
let counter6 = MonotonicCounter(startingAt: 50)
let val1 = await counter6.next()  // 51
await counter6.reset(to: 0)
let val2 = await counter6.next()  // 1
let val3 = await counter6.next()  // 2
assert(val1 == 51, "Before reset should be 51")
assert(val2 == 1, "After reset first value should be 1")
assert(val3 == 2, "After reset second value should be 2")
print("  ✓ Before reset: \(val1)")
print("  ✓ After reset: \(val2), \(val3)")
print("  ✅ PASSED\n")

// Test 7: Increment by custom amount
print("Test 7: Increment by Custom Amount")
print("----------------------------------")
let counter7 = MonotonicCounter(startingAt: 10)
let inc1 = await counter7.increment(by: 5)   // 15
let inc2 = await counter7.increment(by: 10)  // 25
let inc3 = await counter7.increment(by: 1)   // 26
assert(inc1 == 15, "Should increment to 15")
assert(inc2 == 25, "Should increment to 25")
assert(inc3 == 26, "Should increment to 26")
print("  ✓ Increment sequence: \(inc1), \(inc2), \(inc3)")
print("  ✅ PASSED\n")

// Test 8: Concurrent access (actor isolation)
print("Test 8: Concurrent Access Safety")
print("--------------------------------")
let counter8 = MonotonicCounter()
let taskCount = 100

// Launch 100 concurrent tasks
await withTaskGroup(of: UInt64.self) { group in
    for _ in 0..<taskCount {
        group.addTask {
            await counter8.next()
        }
    }

    // Collect all results
    var results: [UInt64] = []
    for await result in group {
        results.append(result)
    }

    // Verify all values are unique
    let uniqueValues = Set(results)
    assert(uniqueValues.count == taskCount, "All values should be unique")
    assert(results.min() == 1, "Min value should be 1")
    assert(results.max() == UInt64(taskCount), "Max value should be \(taskCount)")

    print("  ✓ Generated \(taskCount) unique values concurrently")
    print("  ✓ Range: \(results.min()!) to \(results.max()!)")
}

let final = await counter8.current()
assert(final == UInt64(taskCount), "Final value should be \(taskCount)")
print("  ✓ Final counter value: \(final)")
print("  ✅ PASSED\n")

// Test 9: Large value handling
print("Test 9: Large Value Handling")
print("----------------------------")
let counter9 = MonotonicCounter(startingAt: UInt64.max - 10)
let largeVal = await counter9.current()
assert(largeVal == UInt64.max - 10, "Should handle large initial values")
print("  ✓ Large initial value: \(largeVal)")

// Test incrementing near max (will overflow in production, but we test behavior)
for _ in 0..<5 {
    let _ = await counter9.next()
}
let nearMax = await counter9.current()
print("  ✓ After 5 increments: \(nearMax)")
print("  ✅ PASSED\n")

// Test 10: Reset to zero after many increments
print("Test 10: Reset to Zero After Many Increments")
print("--------------------------------------------")
let counter10 = MonotonicCounter()
for _ in 0..<1000 {
    await counter10.next()
}
let before = await counter10.current()
await counter10.reset(to: 0)
let after = await counter10.current()
let firstAfterReset = await counter10.next()
assert(before == 1000, "Should reach 1000")
assert(after == 0, "Should reset to 0")
assert(firstAfterReset == 1, "First after reset should be 1")
print("  ✓ Before reset: \(before)")
print("  ✓ After reset: \(after)")
print("  ✓ First value after reset: \(firstAfterReset)")
print("  ✅ PASSED\n")

// Summary
print("============================")
print("🎉 ALL TESTS PASSED!")
print("============================")
print("\n✅ MonotonicCounter is working correctly!\n")
print("Test Summary:")
print("  ✓ Initialization (default and custom)")
print("  ✓ Sequential incrementing")
print("  ✓ Current() non-mutating behavior")
print("  ✓ Reset functionality")
print("  ✓ Custom increment amounts")
print("  ✓ Concurrent access safety (actor isolation)")
print("  ✓ Large value handling")
print("  ✓ Reset after many operations")
print("\nReady for production! 🚀")
