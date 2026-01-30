# macOS App Testable Utilities & Logic - Extraction Plan

## 🎯 Goal
Identify and extract **pure logic and stateful utilities** from the macOS app that can be unit tested without requiring integration with SwiftUI, SQLite, or network services.

---

## ✅ Already Tested

### 1. **HTTPPipelineQueue** ✅
- **Location**: `Utils/HTTPPipelineQueue.swift`
- **Tests**: `test_http_pipeline.swift` (5 tests passing)
- **What it tests**: Pipeline queueing, concurrency limits, retry logic, exponential backoff
- **Status**: ✅ **COMPLETE**

---

## 🔥 High Priority: Pure Logic Utils (No Dependencies)

### 2. **ClaudeOutputParser** ⭐️⭐️⭐️
- **Location**: `Services/ClaudeOutputParser.swift`
- **Lines**: 257 lines
- **Complexity**: HIGH - Complex state machine with buffer management
- **What it does**:
  - Parses streaming Claude CLI output into structured types
  - Detects code blocks (```language), todo items (- [ ]), file changes, tool use
  - Handles ANSI escape codes
  - Maintains state: `buffer`, `inCodeBlock`, `codeBlockLanguage`, `codeBlockContent`

**Why testable**:
- ✅ Pure logic - no I/O, no database, no network
- ✅ Stateful parsing with edge cases
- ✅ Complex regex and string manipulation
- ✅ Already has `reset()` method for test isolation

**Proposed Utils**:
```swift
// Utils/StreamingParser.swift
class StreamingParser<T> {
    private var buffer: String = ""

    func parse(_ chunk: String) -> [T]
    func finalize() -> [T]
    func reset()
}

// Utils/ClaudeOutputParser.swift (refactored to use StreamingParser)
class ClaudeOutputParser: StreamingParser<MessageContent> {
    // Specific parsing logic for Claude output
}
```

**Test Cases** (10+ tests):
1. ✅ Parse single code block with language
2. ✅ Parse nested code blocks (should handle or reject)
3. ✅ Parse todo items with different statuses (pending, completed, in-progress)
4. ✅ Parse file changes (Created, Modified, Deleted)
5. ✅ Parse tool use with spinner patterns
6. ✅ Strip ANSI codes correctly
7. ✅ Handle incomplete buffer (partial lines)
8. ✅ Finalize with open code block
9. ✅ Detect interactive prompts with numbered options
10. ✅ Handle empty chunks and whitespace
11. ✅ Handle rapid streaming (multiple chunks concatenated)
12. ✅ Buffer management under high load

---

### 3. **CryptoService (Pure Functions)** ⭐️⭐️⭐️
- **Location**: `Services/CryptoService.swift`
- **Lines**: 342 lines
- **Complexity**: MEDIUM-HIGH - Cryptographic operations
- **What it does**:
  - X25519 key generation and ECDH key agreement
  - HKDF key derivation with context strings
  - ChaCha20-Poly1305 encryption/decryption
  - Base64 encoding/decoding
  - Device ID ordering (lexicographic)

**Why testable**:
- ✅ Pure cryptographic operations
- ✅ Deterministic given same inputs
- ✅ Critical security code that MUST be tested
- ✅ Can test with known test vectors

**Proposed Utils**:
```swift
// Utils/CryptoUtils.swift
struct CryptoUtils {
    // Pure functions only
    static func orderDeviceIds(_ id1: String, _ id2: String) -> (smaller: String, larger: String)
    static func deriveKeyInfo(context: PairwiseContext, sessionId: String) -> String
    static func validateKeySize(_ data: Data) throws
    static func validateNonceSize(_ data: Data) throws
}

// Services/CryptoService.swift (testable operations)
// Keep stateless operations, extract pure functions
```

**Test Cases** (15+ tests):
1. ✅ Generate X25519 key pair (validate 32-byte keys)
2. ✅ ECDH key agreement (deterministic shared secret)
3. ✅ HKDF key derivation with different contexts
4. ✅ Encrypt/decrypt round-trip with ChaCha20-Poly1305
5. ✅ Encrypt/decrypt with additional authenticated data (AAD)
6. ✅ Decrypt with wrong key (should fail)
7. ✅ Decrypt with tampered ciphertext (should fail auth)
8. ✅ Base64 encoding/decoding of keys
9. ✅ Order device IDs lexicographically
10. ✅ Invalid key size handling (should throw)
11. ✅ Invalid nonce size handling (should throw)
12. ✅ Public key from Base64 (valid and invalid)
13. ✅ EncryptedMessage combined format (nonce + ciphertext + tag)
14. ✅ SymmetricKey from Base64 (valid and invalid)
15. ✅ Random bytes generation (check length and uniqueness)

---

### 4. **SequenceGenerator** ⭐️⭐️
- **Location**: `Services/Outbox/SequenceGenerator.swift`
- **Lines**: 59 lines
- **Complexity**: LOW - Simple counter with actor isolation
- **What it does**:
  - Generates monotonically increasing sequence numbers per session
  - Thread-safe via actor isolation
  - Recovers from SQLite on startup

**Why testable**:
- ✅ Simple logic: increment counter
- ✅ Already has `reset(to:)` for testing
- ✅ Can mock database dependency

**Proposed Utils**:
```swift
// Utils/MonotonicCounter.swift
actor MonotonicCounter {
    private var value: UInt64

    init(startingAt: UInt64 = 0)
    func next() -> UInt64
    func current() -> UInt64
    func reset(to value: UInt64)
}

// Services/Outbox/SequenceGenerator.swift (uses MonotonicCounter + DB)
actor SequenceGenerator {
    private let counter: MonotonicCounter
    private let sessionId: String
    private let db: DatabaseWriter

    init(sessionId: String, db: DatabaseWriter) async throws {
        let maxSeq = try await loadMaxSequence(db, sessionId)
        self.counter = MonotonicCounter(startingAt: maxSeq)
    }

    func next() async -> UInt64 {
        await counter.next()
    }
}
```

**Test Cases** (8 tests):
1. ✅ Initialize counter at 0
2. ✅ Next increments by 1
3. ✅ Multiple calls increment sequentially
4. ✅ Current returns value without incrementing
5. ✅ Reset to specific value
6. ✅ Reset and continue from new value
7. ✅ Concurrent access (actor isolation)
8. ✅ UInt64 overflow behavior (edge case)

---

### 5. **DeepLinkRouter (URL Parsing)** ⭐️⭐️
- **Location**: `Services/DeepLinkRouter.swift`
- **Lines**: 117 lines
- **Complexity**: MEDIUM - URL parsing with pattern matching
- **What it does**:
  - Parses deep link URLs into structured routes
  - Handles auth callbacks, navigation routes
  - Extracts IDs from URL paths

**Why testable**:
- ✅ Pure URL parsing logic
- ✅ No side effects in `parse()` method
- ✅ Clear input/output contract

**Proposed Utils**:
```swift
// Utils/URLRouter.swift
protocol RouteType {}

struct URLRouter<Route: RouteType> {
    let scheme: String
    let routes: [String: (URL) -> Route?]

    func parse(_ url: URL) -> Route?
}

// Services/DeepLinkRouter.swift (uses URLRouter)
final class DeepLinkRouter {
    private let router: URLRouter<DeepLinkRoute>

    func parse(_ url: URL) -> DeepLinkRoute {
        router.parse(url) ?? .unknown(url.absoluteString)
    }
}
```

**Test Cases** (12 tests):
1. ✅ Parse auth callback URL with code parameter
2. ✅ Parse dashboard route
3. ✅ Parse settings route
4. ✅ Parse chat route with ID
5. ✅ Parse device route with ID
6. ✅ Unknown URL scheme returns .unknown
7. ✅ Unknown host returns .unknown
8. ✅ Empty path for chat/device returns .unknown
9. ✅ URL with query parameters preserved
10. ✅ URL with fragments preserved
11. ✅ Case sensitivity handling
12. ✅ Special characters in IDs (URL encoding)

---

## 🟡 Medium Priority: Stateful Logic (Minimal Dependencies)

### 6. **OutboxQueue (State Machine)** ⭐️⭐️
- **Location**: `Services/Outbox/OutboxQueue.swift`
- **Lines**: 292 lines
- **Complexity**: HIGH - Complex state management
- **What it does**:
  - Manages in-memory queue synced with SQLite
  - Batch creation, acknowledgment, failure handling
  - In-flight batch tracking
  - Retry logic with event re-queueing

**Why testable (with mock DB)**:
- ⚠️ Requires database abstraction
- ✅ Core logic: queue management, batch creation
- ✅ State transitions: pending → sent → acked/failed

**Proposed Utils**:
```swift
// Utils/BatchQueue.swift
actor BatchQueue<Event: Identifiable & Sendable> {
    private var pending: [Event] = []
    private var inFlight: [String: [Event]] = [:]

    let maxInFlightBatches: Int
    let batchSize: Int

    func append(_ event: Event)
    func getNextBatch() -> (batchId: String, events: [Event])?
    func acknowledgeBatch(batchId: String)
    func handleBatchFailure(batchId: String) -> [Event]
    func getStats() -> (pending: Int, inFlight: Int)
}

// Services/Outbox/OutboxQueue.swift (uses BatchQueue + DB persistence)
```

**Test Cases** (12 tests):
1. ✅ Append event to empty queue
2. ✅ Get next batch respects batch size
3. ✅ Get next batch respects max in-flight limit
4. ✅ Get next batch returns nil when limit reached
5. ✅ Acknowledge batch removes from in-flight
6. ✅ Handle batch failure returns events to pending
7. ✅ Failed events maintain sequence order
8. ✅ Failed events increment retry count
9. ✅ Stats reflect current queue state
10. ✅ Multiple batches in-flight simultaneously
11. ✅ Acknowledge non-existent batch (no crash)
12. ✅ Concurrent access safety (actor isolation)

---

### 7. **MessageContent Parsing Utilities** ⭐️
- **Location**: `Models/ClaudeModels.swift` (likely)
- **What it needs**:
  - TODO item parsing: `- [ ]`, `- [x]`, `- [~]`
  - File change parsing: `Created:`, `Modified:`, `Deleted:`
  - Tool use parsing: spinner patterns, status indicators
  - Markdown code block parsing

**Proposed Utils**:
```swift
// Utils/TextPatternMatcher.swift
struct TextPatternMatcher {
    static func matchTodoItem(_ line: String) -> TodoItem?
    static func matchFileChange(_ line: String) -> FileChange?
    static func matchToolUse(_ line: String) -> ToolUse?
    static func matchCodeBlockStart(_ line: String) -> String?
    static func matchCodeBlockEnd(_ line: String) -> Bool
}
```

**Test Cases** (15 tests):
1. ✅ Match `- [ ]` as pending todo
2. ✅ Match `- [x]` as completed todo
3. ✅ Match `- [~]` as in-progress todo
4. ✅ Match `✓` as completed
5. ✅ Match `Created: path/to/file`
6. ✅ Match `Modified: path/to/file`
7. ✅ Match `Deleted: path/to/file`
8. ✅ Match spinner pattern `⠋ Running: cmd`
9. ✅ Match `✓ Completed: cmd`
10. ✅ Match `✗ Failed: cmd`
11. ✅ Match code block start \`\`\`swift
12. ✅ Match code block end \`\`\`
13. ✅ Ignore invalid patterns
14. ✅ Handle whitespace variations
15. ✅ Handle Unicode and emoji correctly

---

## 🟢 Low Priority: Helpers & Extensions

### 8. **String Extensions** ⭐️
- **Common utilities**:
  - Trimming whitespace
  - Prefix/suffix checking
  - UUID validation
  - Base64 encoding/decoding
  - Path manipulation

**Proposed Utils**:
```swift
// Utils/StringExtensions.swift
extension String {
    var trimmed: String
    func hasPrefix(oneOf: [String]) -> Bool
    func isValidUUID() -> Bool
    var base64Encoded: String?
    var base64Decoded: String?
}
```

### 9. **Date Extensions** ⭐️
- **Common utilities**:
  - Relative time formatting ("2 hours ago")
  - ISO8601 parsing/formatting
  - Time interval calculations

**Proposed Utils**:
```swift
// Utils/DateExtensions.swift
extension Date {
    func timeAgo() -> String
    var iso8601String: String
    func adding(seconds: TimeInterval) -> Date
}
```

### 10. **Data Extensions** ⭐️
- **Common utilities**:
  - Hex string conversion
  - Base64 encoding/decoding
  - Size formatting

**Proposed Utils**:
```swift
// Utils/DataExtensions.swift
extension Data {
    var hexString: String
    init?(hexString: String)
    var formattedSize: String  // "1.2 MB"
}
```

---

## 🚫 NOT Testable as Utils (Integration Tests Only)

These require full integration testing, not unit tests:

1. **DatabaseService** - Requires real SQLite
2. **RelayClientService** - Requires network/HTTP
3. **ClaudeService** - Requires process spawning
4. **AuthService** - Requires OAuth flow
5. **FileSystemService** - Requires file I/O
6. **GitService** - Requires git binary
7. **KeychainService** - Requires macOS Keychain access
8. **SecureEnclaveKeyService** - Requires Secure Enclave hardware

---

## 📋 Implementation Priority

### Phase 1: Critical Pure Logic (Week 1)
1. ✅ **HTTPPipelineQueue** (DONE)
2. ⏭️ **ClaudeOutputParser** (High complexity, high value)
3. ⏭️ **CryptoService** (Security-critical, must test)

### Phase 2: State Management (Week 2)
4. ⏭️ **SequenceGenerator** / **MonotonicCounter**
5. ⏭️ **OutboxQueue** / **BatchQueue**
6. ⏭️ **DeepLinkRouter** / **URLRouter**

### Phase 3: Helpers & Extensions (Week 3)
7. ⏭️ **TextPatternMatcher** (from ClaudeOutputParser)
8. ⏭️ **String/Data/Date Extensions**

---

## 🎯 Testing Strategy

### Unit Test Structure
```swift
// apps/macos/unbound-macosTests/Utils/ClaudeOutputParserTests.swift
import XCTest
@testable import unbound_macos

final class ClaudeOutputParserTests: XCTestCase {
    var parser: ClaudeOutputParser!

    override func setUp() {
        super.setUp()
        parser = ClaudeOutputParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    func testParseCodeBlock() {
        // Given
        let input = """
        ```swift
        let x = 5
        ```
        """

        // When
        let contents = parser.parse(input)
        let finalized = parser.finalize()

        // Then
        XCTAssertEqual(finalized.count, 1)
        // ...
    }
}
```

### Standalone Test Files (for non-XCTest)
- Continue using standalone Swift test files like `test_http_pipeline.swift`
- Faster to run, no Xcode project setup needed
- Better for CI/CD pipelines

---

## 📊 Success Metrics

### Code Coverage Target: 80%+
- **Utilities**: 90%+ coverage (pure logic)
- **State machines**: 80%+ coverage (OutboxQueue, SequenceGenerator)
- **Parsers**: 85%+ coverage (ClaudeOutputParser)
- **Crypto**: 95%+ coverage (security-critical)

### Performance Targets
- Each test file completes in < 5 seconds
- Individual test cases complete in < 100ms
- No flaky tests (100% reproducible)

---

## 🔧 Tooling

### Test Execution
```bash
# Standalone tests
swift apps/macos/test_claude_parser.swift
swift apps/macos/test_crypto_utils.swift
swift apps/macos/test_sequence_generator.swift

# XCTest (when integrated into Xcode project)
xcodebuild test -scheme unbound-macos -destination 'platform=macOS'
```

### Continuous Integration
```yaml
# .github/workflows/macos-tests.yml
- name: Run macOS Utils Tests
  run: |
    swift apps/macos/test_http_pipeline.swift
    swift apps/macos/test_claude_parser.swift
    swift apps/macos/test_crypto_utils.swift
```

---

## 📚 Documentation

For each extracted utility, create:
1. **README.md** - Usage examples and API documentation
2. **TESTING.md** - Test coverage report and known edge cases
3. **IMPLEMENTATION_NOTES.md** - Design decisions and architectural notes

---

## ✅ Summary

**Total Testable Utilities**: 10 identified

**Breakdown by Priority**:
- 🔥 High Priority: 5 (ClaudeOutputParser, CryptoService, SequenceGenerator, DeepLinkRouter, OutboxQueue)
- 🟡 Medium Priority: 2 (MessageContent parsing, BatchQueue)
- 🟢 Low Priority: 3 (String/Data/Date extensions)

**Estimated Test Coverage**: 200+ unit tests across all utilities

**Timeline**: 3-4 weeks for complete coverage

**Next Steps**:
1. ✅ HTTPPipelineQueue (DONE)
2. Start with **ClaudeOutputParser** (highest complexity, highest value)
3. Follow with **CryptoService** (security-critical)
4. Continue with state management utilities
