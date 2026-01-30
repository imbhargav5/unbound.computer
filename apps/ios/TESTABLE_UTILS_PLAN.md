# iOS App Testable Utilities & Logic - Extraction Plan

## 🎯 Goal
Identify and extract **pure logic and stateful utilities** from the iOS app that can be unit tested without requiring integration with SwiftUI, SQLite, or network services.

**Approach**: Mirror the successful macOS implementation, adapting for iOS-specific patterns.

---

## 📊 iOS vs macOS Analysis

**Codebase Size**: 81 Swift files (vs 103 on macOS)
**Architecture**: Similar services-based architecture
**Shared Code**: CryptoService, DeepLinkRouter have identical structure
**iOS-Specific**: Live Activities, Push Notifications, Session Viewer

---

## ✅ Reusable from macOS

These utilities can be **directly copied** from macOS with minimal changes:

### 1. **MonotonicCounter** ✅ (Can Copy)
**Source**: `apps/macos/unbound-macos/Utils/MonotonicCounter.swift`
**Destination**: `apps/ios/unbound-ios/Utils/MonotonicCounter.swift`
**Changes**: None required (pure Swift, no platform dependencies)
**Tests**: Copy `test_monotonic_counter.swift` as-is

### 2. **StreamingParser** ✅ (Can Copy)
**Source**: `apps/macos/unbound-macos/Utils/StreamingParser.swift`
**Destination**: `apps/ios/unbound-ios/Utils/StreamingParser.swift`
**Changes**: None required (generic base class)

### 3. **CryptoUtils** ⚠️ (Needs Adaptation)
**Source**: `apps/macos/unbound-macos/Utils/CryptoUtils.swift`
**Destination**: `apps/ios/unbound-ios/Utils/CryptoUtils.swift`
**Changes Required**:
- **Nonce size**: iOS uses **XChaCha20-Poly1305** (24-byte nonce)
- macOS uses **ChaCha20-Poly1305** (12-byte nonce)
- Update `validateNonceSize()` from 12 → 24 bytes
- Update `parseEncryptedMessage()` minimum from 28 → 40 bytes (24 nonce + 16 tag)

**Key Difference**:
```swift
// macOS (ChaCha20)
static func validateNonceSize(_ data: Data) throws {
    guard data.count == 12 else {  // ← 12 bytes
        throw CryptoError.invalidNonceSize
    }
}

// iOS (XChaCha20)
static func validateNonceSize(_ data: Data) throws {
    guard data.count == 24 else {  // ← 24 bytes
        throw CryptoError.invalidNonceSize
    }
}
```

### 4. **DeepLinkRouter** ✅ (Can Copy with Minor Changes)
**Source**: `apps/macos/unbound-macos/Services/DeepLinkRouter.swift`
**Destination**: `apps/ios/unbound-ios/Services/DeepLinkRouter.swift`
**Status**: Already exists and nearly identical
**Changes**: Add `Hashable` conformance to `DeepLinkRoute` (iOS has this, macOS doesn't)
**Tests**: Copy `test_url_router.swift` (when created)

---

## 🔥 High Priority: iOS-Specific Logic to Test

### 5. **ActiveSessionManager** ⭐⭐⭐
**Location**: `Models/ActiveSessionManager.swift`
**Purpose**: Manages active coding session state (iOS viewer)
**What it likely does**:
- Tracks current active session
- Session lifecycle (start, pause, resume, end)
- Session switching
- State persistence

**Why testable**:
- ✅ State machine logic
- ✅ Session transitions
- ⚠️ May have database dependencies (abstract away)

**Proposed Util**:
```swift
// Utils/SessionStateMachine.swift
actor SessionStateMachine<SessionID: Hashable & Sendable> {
    enum State {
        case idle
        case active(SessionID)
        case paused(SessionID)
    }

    private var state: State = .idle

    func startSession(_ id: SessionID) throws
    func pauseSession() throws
    func resumeSession() throws
    func endSession() throws
    func getCurrentSession() -> SessionID?
}
```

**Test Cases** (10 tests):
1. ✅ Start session from idle
2. ✅ Pause active session
3. ✅ Resume paused session
4. ✅ End active session
5. ✅ Cannot pause when idle
6. ✅ Cannot resume when not paused
7. ✅ Switch sessions (end + start)
8. ✅ Get current session (active, paused, idle)
9. ✅ Concurrent state changes (actor isolation)
10. ✅ State persistence across resets

---

### 6. **LiveActivityManager** ⭐⭐
**Location**: `Models/LiveActivityManager.swift`
**Purpose**: Manages iOS Live Activities for coding sessions
**What it likely does**:
- Create/update/end Live Activities
- Format activity content
- Activity state management

**Why testable (partially)**:
- ✅ Content formatting logic
- ✅ State transitions
- ❌ ActivityKit integration (not testable)

**Proposed Util**:
```swift
// Utils/ActivityContentFormatter.swift
struct ActivityContentFormatter {
    static func formatDuration(_ seconds: TimeInterval) -> String
    static func formatProgress(current: Int, total: Int) -> Double
    static func formatStatus(_ status: SessionStatus) -> String
    static func shouldUpdateActivity(old: ActivityContent, new: ActivityContent) -> Bool
}
```

**Test Cases** (8 tests):
1. ✅ Format duration (seconds → "1m 30s")
2. ✅ Format duration (hours → "1h 23m")
3. ✅ Calculate progress percentage
4. ✅ Format status strings
5. ✅ Detect significant changes (should update)
6. ✅ Ignore minor changes (throttle updates)
7. ✅ Handle edge cases (0 seconds, negative values)
8. ✅ Handle very long durations

---

### 7. **ChatContent** ⭐⭐
**Location**: `Models/ChatContent.swift`
**Purpose**: Represents different types of chat message content
**What it likely does**:
- Parse/represent message types (text, code, images, etc.)
- Content validation
- Content rendering hints

**Why testable**:
- ✅ Content type detection
- ✅ Validation logic
- ✅ Parsing/formatting

**Proposed Util**:
```swift
// Utils/ContentTypeDetector.swift
struct ContentTypeDetector {
    static func detectType(_ content: String) -> ContentType
    static func isCodeBlock(_ content: String) -> Bool
    static func extractLanguage(from codeBlock: String) -> String?
    static func isImageURL(_ content: String) -> Bool
    static func sanitizeHTML(_ html: String) -> String
}
```

**Test Cases** (10 tests):
1. ✅ Detect code block (```language)
2. ✅ Extract language from code block
3. ✅ Detect plain text
4. ✅ Detect image URLs
5. ✅ Detect markdown links
6. ✅ Sanitize HTML (remove scripts)
7. ✅ Handle malformed code blocks
8. ✅ Handle empty content
9. ✅ Handle very long content
10. ✅ Detect multiple content types in sequence

---

### 8. **Message** ⭐
**Location**: `Models/Message.swift`
**Purpose**: Message model with metadata
**What it likely does**:
- Message validation
- Timestamp handling
- Message comparison/sorting

**Proposed Util**:
```swift
// Utils/MessageUtils.swift
struct MessageUtils {
    static func sortByTimestamp(_ messages: [Message]) -> [Message]
    static func groupByDate(_ messages: [Message]) -> [Date: [Message]]
    static func filterByType(_ messages: [Message], type: MessageType) -> [Message]
    static func validateMessageContent(_ content: String) -> Bool
    static func truncatePreview(_ content: String, maxLength: Int) -> String
}
```

**Test Cases** (8 tests):
1. ✅ Sort messages by timestamp (ascending/descending)
2. ✅ Group messages by date
3. ✅ Filter by message type
4. ✅ Validate content length
5. ✅ Truncate long previews
6. ✅ Handle empty message lists
7. ✅ Handle same timestamps (stable sort)
8. ✅ Handle edge case dates

---

## 🟡 Medium Priority: Shared Logic (Similar to macOS)

### 9. **CryptoService** ⭐⭐⭐ (High Value)
**Location**: `Services/CryptoService.swift`
**Status**: Nearly identical to macOS except XChaCha20 vs ChaCha20
**Action**: Adapt macOS `CryptoUtils` for iOS (24-byte nonce instead of 12-byte)

**Test Cases**: 20+ tests (copy from macOS, adjust nonce sizes)

---

### 10. **DeepLinkRouter** ⭐⭐
**Location**: `Services/DeepLinkRouter.swift`
**Status**: Already exists, nearly identical to macOS
**Action**: Use macOS test cases directly

**Test Cases**: 12 tests (copy from macOS when created)

---

## 🟢 Low Priority: Extensions & Helpers

### 11. **Date Extensions** ⭐
**Use Cases**:
- Relative time formatting ("2 hours ago")
- Session duration formatting
- Date grouping for messages

**Proposed Util**:
```swift
// Utils/DateExtensions.swift
extension Date {
    func timeAgo() -> String
    func formatted(style: DateFormatStyle) -> String
    func isSameDay(as other: Date) -> Bool
    func startOfDay() -> Date
    func durationSince(_ date: Date) -> TimeInterval
}
```

**Test Cases** (8 tests):
1. ✅ Format "just now" (< 1 minute)
2. ✅ Format "5 minutes ago"
3. ✅ Format "2 hours ago"
4. ✅ Format "yesterday"
5. ✅ Format "3 days ago"
6. ✅ Check same day
7. ✅ Get start of day
8. ✅ Calculate duration

---

### 12. **String Extensions** ⭐
**Use Cases**:
- UUID validation
- Content sanitization
- Truncation

**Proposed Util**:
```swift
// Utils/StringExtensions.swift
extension String {
    var isValidUUID: Bool
    var trimmed: String
    func truncated(to length: Int, trailing: String = "...") -> String
    func removingEmojis() -> String
    var base64Encoded: String?
    var base64Decoded: String?
}
```

---

## 🚫 NOT Testable as Utils (Integration Only)

These require full integration testing, not unit tests:

1. **DatabaseService** - Requires real SQLite
2. **RelayConnectionService** - Requires network/WebSocket
3. **AuthService** - Requires OAuth flow
4. **PushNotificationService** - Requires APNs
5. **KeychainService** - Requires iOS Keychain
6. **SessionSecretService** - Requires Secure Enclave (iOS-specific)
7. **MessageEncryptionService** - Requires crypto + database

---

## 📋 Implementation Priority (iOS)

### ✅ Phase 0: Copy from macOS (Week 1)
**Action**: Direct copy with minimal changes

1. ✅ **MonotonicCounter** (52 lines) - Copy as-is
   - Copy file: `Utils/MonotonicCounter.swift`
   - Copy tests: `test_monotonic_counter.swift`
   - Status: Ready to use immediately

2. ✅ **StreamingParser** (73 lines) - Copy as-is
   - Copy file: `Utils/StreamingParser.swift`
   - Status: Ready if needed for iOS (currently no streaming parser on iOS)

3. ⏭️ **CryptoUtils** (206 lines) - Adapt for XChaCha20
   - Copy file: `Utils/CryptoUtils.swift`
   - Modify: Nonce size 12 → 24 bytes
   - Copy tests: `test_crypto_utils.swift`
   - Adjust test assertions for 24-byte nonces

### ⏭️ Phase 1: iOS-Specific Logic (Week 2)

4. ⏭️ **SessionStateMachine** (NEW) - Extract from ActiveSessionManager
   - Create: `Utils/SessionStateMachine.swift`
   - Tests: `test_session_state.swift` (10 tests)
   - Complexity: MEDIUM - State machine with transitions

5. ⏭️ **ActivityContentFormatter** (NEW) - Extract from LiveActivityManager
   - Create: `Utils/ActivityContentFormatter.swift`
   - Tests: `test_activity_formatter.swift` (8 tests)
   - Complexity: LOW - Pure formatting functions

6. ⏭️ **ContentTypeDetector** (NEW) - Extract from ChatContent
   - Create: `Utils/ContentTypeDetector.swift`
   - Tests: `test_content_detector.swift` (10 tests)
   - Complexity: MEDIUM - Pattern matching and validation

### ⏭️ Phase 2: Message & Date Utils (Week 3)

7. ⏭️ **MessageUtils** (NEW)
   - Create: `Utils/MessageUtils.swift`
   - Tests: `test_message_utils.swift` (8 tests)
   - Complexity: LOW - Sorting and filtering

8. ⏭️ **DateExtensions** (NEW)
   - Create: `Utils/DateExtensions.swift`
   - Tests: `test_date_extensions.swift` (8 tests)
   - Complexity: LOW - Date formatting and comparison

9. ⏭️ **StringExtensions** (NEW)
   - Create: `Utils/StringExtensions.swift`
   - Tests: `test_string_extensions.swift` (10 tests)
   - Complexity: LOW - String manipulation

---

## 🎯 iOS vs macOS: Key Differences

| Aspect | macOS | iOS | Impact |
|--------|-------|-----|--------|
| **Crypto** | ChaCha20 (12-byte nonce) | XChaCha20 (24-byte nonce) | ⚠️ Tests need adjustment |
| **Outbox** | Has event outbox + pipeline | No outbox (viewer only) | ✅ Can copy MonotonicCounter |
| **Parser** | ClaudeOutputParser (complex) | ChatContent (simpler) | ℹ️ Different use case |
| **Sessions** | Multiple simultaneous | Single active session | ⚠️ Different state logic |
| **Live Activities** | N/A (macOS) | iOS-specific feature | ✨ New testable logic |
| **Architecture** | Matches iOS closely | Matches macOS closely | ✅ Easy to share utils |

---

## 📊 Estimated Test Coverage

| Utility | Source | Tests | Lines | Effort |
|---------|--------|-------|-------|--------|
| MonotonicCounter | macOS (copy) | 10 | 52 | 5 min |
| StreamingParser | macOS (copy) | (base) | 73 | 5 min |
| CryptoUtils | macOS (adapt) | 20 | 206 | 30 min |
| SessionStateMachine | NEW | 10 | ~100 | 4 hours |
| ActivityContentFormatter | NEW | 8 | ~80 | 2 hours |
| ContentTypeDetector | NEW | 10 | ~100 | 3 hours |
| MessageUtils | NEW | 8 | ~80 | 2 hours |
| DateExtensions | NEW | 8 | ~60 | 2 hours |
| StringExtensions | NEW | 10 | ~80 | 2 hours |
| **TOTAL** | **Mixed** | **84** | **~831** | **~18 hours** |

---

## 🎓 Testing Strategy

### Standalone Swift Tests (Like macOS)
```bash
# Create test files in ios/ directory
apps/ios/
├── test_monotonic_counter.swift ✅ (copy from macOS)
├── test_crypto_utils_ios.swift ⏭️ (adapted for XChaCha20)
├── test_session_state.swift ⏭️ (new)
├── test_activity_formatter.swift ⏭️ (new)
├── test_content_detector.swift ⏭️ (new)
├── test_message_utils.swift ⏭️ (new)
├── test_date_extensions.swift ⏭️ (new)
└── test_string_extensions.swift ⏭️ (new)

# Run tests
cd apps/ios
swift test_monotonic_counter.swift
swift test_crypto_utils_ios.swift
# ... etc
```

### XCTest Integration (Optional)
- Add to Xcode project for CI/CD
- Use same test logic in `XCTestCase` wrappers
- Run via `xcodebuild test`

---

## ✅ Success Criteria (iOS)

| Criterion | Target | Strategy |
|-----------|--------|----------|
| Test Coverage | 85%+ | Focus on pure logic & state |
| Test Count | 80+ | Comprehensive edge cases |
| Build Success | No regressions | Verify Xcode builds |
| Test Speed | < 5s per file | Standalone Swift tests |
| Reproducibility | 100% | Deterministic tests only |
| Reuse from macOS | 50%+ | Copy MonotonicCounter, adapt CryptoUtils |

---

## 🚀 Quick Start (iOS)

### Step 1: Copy MonotonicCounter from macOS (5 minutes)
```bash
cd apps/ios

# Copy utility
cp ../macos/unbound-macos/Utils/MonotonicCounter.swift \
   unbound-ios/Utils/MonotonicCounter.swift

# Copy test
cp ../macos/test_monotonic_counter.swift \
   test_monotonic_counter.swift

# Run test
swift test_monotonic_counter.swift
# ✅ ALL TESTS PASSED!
```

### Step 2: Adapt CryptoUtils for iOS (30 minutes)
```bash
# Copy utility
cp ../macos/unbound-macos/Utils/CryptoUtils.swift \
   unbound-ios/Utils/CryptoUtils.swift

# Edit: Change nonce size from 12 → 24 bytes
# Edit: Update parseEncryptedMessage minimum from 28 → 40 bytes

# Copy and adapt test
cp ../macos/test_crypto_utils.swift \
   test_crypto_utils_ios.swift

# Edit: Update nonce test assertions (12 → 24 bytes)

# Run test
swift test_crypto_utils_ios.swift
# ✅ ALL TESTS PASSED!
```

### Step 3: Build Verification
```bash
# Build iOS app to verify no regressions
xcodebuild -project unbound-ios.xcodeproj \
           -scheme unbound-ios \
           -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
           clean build
# ** BUILD SUCCEEDED **
```

---

## 📝 Documentation Plan

For each iOS utility, create:

1. **README.md** - Usage examples and API docs
2. **TESTING.md** - Test coverage report
3. **IOS_SPECIFIC_NOTES.md** - Differences from macOS

---

## ✨ Summary

**iOS App Testable Utilities**: 9 utilities identified
- 3 can be copied directly from macOS ✅
- 1 needs adaptation (nonce size change) ⚠️
- 5 are iOS-specific and need new implementation ✨

**Estimated Timeline**: 3 weeks for complete coverage
- Week 1: Copy/adapt from macOS (3 utilities)
- Week 2: iOS-specific logic (3 utilities)
- Week 3: Extensions and helpers (3 utilities)

**Test Count**: 84+ tests across all utilities
**Lines of Code**: ~831 lines (utilities) + ~600 lines (tests)

**Benefits**:
- ✅ Share utilities with macOS where possible
- ✅ 85%+ test coverage on pure logic
- ✅ Fast feedback loop (standalone tests)
- ✅ iOS-specific features (Live Activities) well-tested

**Next Action**: Copy `MonotonicCounter` from macOS (5 minutes) 🚀
