# macOS Testable Utilities - Quick Reference

## 🎯 Strategy: Test Logic & State, Not Integration

**Focus**: Pure functions, state machines, parsers, and algorithms
**Avoid**: Database I/O, network calls, file system operations, UI integration

---

## 🔥 Top 5 High-Value Testable Utilities

### 1. **ClaudeOutputParser** ⭐⭐⭐
**Why**: Complex state machine with buffer management, regex, and streaming
**Value**: Catches parsing bugs that affect user experience
**Lines**: 257
**Tests**: 12+ test cases
**Extracts to**: `Utils/StreamingParser.swift` (generic base class)

### 2. **CryptoService** ⭐⭐⭐
**Why**: Security-critical code must be validated
**Value**: Prevents encryption/decryption bugs and key derivation errors
**Lines**: 342
**Tests**: 15+ test cases
**Extracts to**: `Utils/CryptoUtils.swift` (pure functions)

### 3. **OutboxQueue** ⭐⭐
**Why**: Complex state management with batch tracking and retries
**Value**: Ensures reliable event delivery and ordering
**Lines**: 292
**Tests**: 12+ test cases
**Extracts to**: `Utils/BatchQueue.swift` (generic queue logic)

### 4. **SequenceGenerator** ⭐⭐
**Why**: Simple but critical for event ordering
**Value**: Guarantees monotonic sequence numbers
**Lines**: 59
**Tests**: 8 test cases
**Extracts to**: `Utils/MonotonicCounter.swift`

### 5. **DeepLinkRouter** ⭐⭐
**Why**: URL parsing with pattern matching
**Value**: Ensures correct navigation and auth callbacks
**Lines**: 117
**Tests**: 12 test cases
**Extracts to**: `Utils/URLRouter.swift` (generic router)

---

## 📋 Implementation Phases

### ✅ Phase 0: Foundation (COMPLETE)
- ✅ **HTTPPipelineQueue** - 5 tests passing
  - Pipeline queueing, concurrency, retry logic, exponential backoff

### ⏭️ Phase 1: Parsers & Crypto (Week 1)
**Priority**: Security and correctness

1. **ClaudeOutputParser** (2 days)
   - Extract streaming parser base class
   - Test code blocks, todos, file changes, tool use
   - Test ANSI code stripping and buffer management

2. **CryptoService** (3 days)
   - Extract pure crypto utility functions
   - Test key generation, ECDH, HKDF, ChaCha20-Poly1305
   - Use known test vectors for validation

### ⏭️ Phase 2: State Machines (Week 2)
**Priority**: Reliability and ordering

3. **SequenceGenerator → MonotonicCounter** (1 day)
   - Test monotonic incrementing
   - Test concurrent access (actor safety)

4. **OutboxQueue → BatchQueue** (2 days)
   - Test batch creation and in-flight tracking
   - Test acknowledgment and failure handling
   - Mock database for isolation

5. **DeepLinkRouter → URLRouter** (1 day)
   - Test URL pattern matching
   - Test route extraction and validation

### ⏭️ Phase 3: Helpers (Week 3)
**Priority**: Code quality

6. **TextPatternMatcher** (1 day)
   - Extract from ClaudeOutputParser
   - Test regex patterns for todos, file changes, tool use

7. **Extensions** (2 days)
   - String extensions (trimming, validation, encoding)
   - Data extensions (hex, base64, size formatting)
   - Date extensions (relative time, ISO8601)

---

## 🧪 Test File Structure

```
apps/macos/
├── unbound-macos/
│   ├── Utils/
│   │   ├── HTTPPipelineQueue.swift ✅
│   │   ├── StreamingParser.swift ⏭️
│   │   ├── MonotonicCounter.swift ⏭️
│   │   ├── BatchQueue.swift ⏭️
│   │   ├── URLRouter.swift ⏭️
│   │   ├── CryptoUtils.swift ⏭️
│   │   └── TextPatternMatcher.swift ⏭️
│   └── Services/
│       ├── ClaudeOutputParser.swift (refactored to use StreamingParser)
│       ├── CryptoService.swift (refactored to use CryptoUtils)
│       └── Outbox/
│           ├── SequenceGenerator.swift (uses MonotonicCounter)
│           └── OutboxQueue.swift (uses BatchQueue)
└── test_*.swift (standalone tests)
    ├── test_http_pipeline.swift ✅ PASSING
    ├── test_claude_parser.swift ⏭️
    ├── test_crypto_utils.swift ⏭️
    ├── test_monotonic_counter.swift ⏭️
    ├── test_batch_queue.swift ⏭️
    ├── test_url_router.swift ⏭️
    └── test_text_patterns.swift ⏭️
```

---

## 🎯 Test Coverage Goals

| Utility | Target Coverage | Test Count | Priority |
|---------|----------------|------------|----------|
| HTTPPipelineQueue | 90% | 5 ✅ | DONE |
| ClaudeOutputParser | 85% | 12 | 🔥 HIGH |
| CryptoService | 95% | 15 | 🔥 HIGH |
| SequenceGenerator | 90% | 8 | 🟡 MED |
| OutboxQueue | 80% | 12 | 🟡 MED |
| DeepLinkRouter | 85% | 12 | 🟡 MED |
| TextPatternMatcher | 90% | 15 | 🟢 LOW |
| Extensions | 80% | 20 | 🟢 LOW |

**Total**: ~99 unit tests across all utilities

---

## 📝 Test Template

```swift
#!/usr/bin/env swift
import Foundation

// Utility implementation
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
}

// Test runner
print("🧪 Testing MonotonicCounter")
print("===========================\n")

// Test 1: Initialize at 0
print("Test 1: Initialize at 0")
let counter1 = MonotonicCounter()
let initial = await counter1.current()
assert(initial == 0, "Should start at 0")
print("  ✅ PASSED\n")

// Test 2: Next increments by 1
print("Test 2: Next increments by 1")
let counter2 = MonotonicCounter()
let first = await counter2.next()
let second = await counter2.next()
assert(first == 1, "First call should return 1")
assert(second == 2, "Second call should return 2")
print("  ✅ PASSED\n")

// Test 3: Current doesn't increment
print("Test 3: Current doesn't increment")
let counter3 = MonotonicCounter()
await counter3.next()  // 1
let curr1 = await counter3.current()  // Still 1
let curr2 = await counter3.current()  // Still 1
assert(curr1 == 1 && curr2 == 1, "Current should not increment")
print("  ✅ PASSED\n")

// Test 4: Reset to specific value
print("Test 4: Reset to specific value")
let counter4 = MonotonicCounter()
await counter4.next()  // 1
await counter4.reset(to: 100)
let afterReset = await counter4.current()
assert(afterReset == 100, "Should reset to 100")
print("  ✅ PASSED\n")

print("🎉 ALL TESTS PASSED!")
```

---

## 🚀 Quick Start

### Run All Tests
```bash
cd apps/macos

# Run existing test
swift test_http_pipeline.swift

# Run new tests (once created)
swift test_claude_parser.swift
swift test_crypto_utils.swift
swift test_monotonic_counter.swift
swift test_batch_queue.swift
```

### Create New Test File
```bash
# 1. Copy template
cp test_http_pipeline.swift test_my_util.swift

# 2. Edit and implement tests
# 3. Run
swift test_my_util.swift
```

---

## ✅ Benefits

### 1. **Fast Feedback**
- Tests run in < 5 seconds
- No Xcode project setup needed
- Instant validation during development

### 2. **High Confidence**
- Critical logic validated: parsing, crypto, queueing
- Edge cases covered: empty input, overflow, concurrent access
- Regression detection: tests prevent breaking changes

### 3. **Better Architecture**
- Forces separation of concerns
- Encourages pure functions and testable design
- Generic utilities become reusable

### 4. **Documentation**
- Tests serve as usage examples
- Expected behavior is explicit
- Edge cases are documented

---

## 🎯 Success Criteria

✅ **80%+ code coverage** across all extracted utilities
✅ **100% reproducible** tests (no flaky tests)
✅ **< 5 seconds** per test file execution
✅ **200+ tests** total across all utilities
✅ **Zero integration dependencies** in unit tests

---

## 📊 Current Status

| Phase | Status | Progress |
|-------|--------|----------|
| Phase 0: Foundation | ✅ COMPLETE | 100% |
| Phase 1: Parsers & Crypto | ⏭️ NEXT | 0% |
| Phase 2: State Machines | 🔜 PLANNED | 0% |
| Phase 3: Helpers | 🔜 PLANNED | 0% |

**Overall Progress**: 1/10 utilities tested (10%)

---

## 🎯 Next Actions

1. ✅ HTTPPipelineQueue tested (DONE)
2. ⏭️ **Start with ClaudeOutputParser** (highest value, complex logic)
3. ⏭️ Follow with CryptoService (security-critical)
4. ⏭️ Continue with state management utilities

**Estimated Timeline**: 3-4 weeks for 80%+ coverage across all utilities
