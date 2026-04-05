#!/usr/bin/env swift
import Foundation

// HTTPPipelineQueue implementation for testing
actor HTTPPipelineQueue<Batch: Sendable> {
    struct Configuration {
        let maxInFlight: Int
        let pollIntervalMS: Int
        let requestTimeout: TimeInterval
        let maxRetries: Int
        let baseRetryDelaySeconds: Double
        let maxRetryDelaySeconds: Double

        static func `default`() -> Configuration {
            Configuration(
                maxInFlight: 3,
                pollIntervalMS: 100,
                requestTimeout: 10.0,
                maxRetries: 10,
                baseRetryDelaySeconds: 1.0,
                maxRetryDelaySeconds: 60.0
            )
        }
    }

    typealias GetNextBatch = () async -> Batch?
    typealias SendBatch = (Batch) async throws -> Void
    typealias OnSuccess = (Batch) async throws -> Void
    typealias OnFailure = (Batch, Error) async throws -> Void

    private let config: Configuration
    private let getNextBatch: GetNextBatch
    private let sendBatch: SendBatch
    private let onSuccess: OnSuccess
    private let onFailure: OnFailure

    private var isRunning = false
    private var pollingTask: Task<Void, Never>?
    private var inFlightCount = 0

    init(
        config: Configuration = .default(),
        getNextBatch: @escaping GetNextBatch,
        sendBatch: @escaping SendBatch,
        onSuccess: @escaping OnSuccess,
        onFailure: @escaping OnFailure
    ) {
        self.config = config
        self.getNextBatch = getNextBatch
        self.sendBatch = sendBatch
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.runPollingLoop()
        }
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    func getInFlightCount() -> Int {
        inFlightCount
    }

    private func runPollingLoop() async {
        while isRunning {
            do {
                if inFlightCount < config.maxInFlight {
                    if let batch = await getNextBatch() {
                        inFlightCount += 1
                        Task.detached(priority: .high) { [weak self] in
                            guard let self else { return }
                            await self.processBatch(batch, retryCount: 0)
                        }
                    }
                }
                try await Task.sleep(nanoseconds: UInt64(config.pollIntervalMS) * 1_000_000)
            } catch {
                if Task.isCancelled {
                    break
                }
            }
        }
    }

    private func processBatch(_ batch: Batch, retryCount: Int) async {
        do {
            try await sendBatch(batch)
            try await onSuccess(batch)
            decrementInFlight()
        } catch {
            await handleBatchError(batch, error: error, retryCount: retryCount)
        }
    }

    private func handleBatchError(
        _ batch: Batch,
        error: Error,
        retryCount: Int
    ) async {
        if retryCount >= config.maxRetries {
            try? await onFailure(batch, error)
            decrementInFlight()
            return
        }

        let retryDelay = min(
            config.baseRetryDelaySeconds * pow(2.0, Double(retryCount)),
            config.maxRetryDelaySeconds
        )

        try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
        await processBatch(batch, retryCount: retryCount + 1)
    }

    private func decrementInFlight() {
        inFlightCount -= 1
    }
}

// Test models
struct TestBatch: Sendable {
    let id: String
    let items: [Int]
}

actor TestState {
    var batches: [TestBatch] = []
    var sentBatches: [String: TestBatch] = [:]
    var successfulBatches: [String] = []
    var failedBatches: [String] = []
    var sendCallCount = 0
    var shouldFail = false
    var failureCount = 0
    var sendTimes: [Date] = []

    func addBatch(_ batch: TestBatch) {
        batches.append(batch)
    }

    func getNext() -> TestBatch? {
        guard !batches.isEmpty else { return nil }
        return batches.removeFirst()
    }

    func recordSend(_ batch: TestBatch) {
        sentBatches[batch.id] = batch
        sendCallCount += 1
        sendTimes.append(Date())
    }

    func recordSuccess(_ id: String) {
        successfulBatches.append(id)
    }

    func recordFailure(_ id: String) {
        failedBatches.append(id)
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func incrementFailureCount() {
        failureCount += 1
    }

    func getSendCallCount() -> Int { sendCallCount }
    func getSuccessful() -> [String] { successfulBatches }
    func getFailed() -> [String] { failedBatches }
    func getFailureCount() -> Int { failureCount }
    func getShouldFail() -> Bool { shouldFail }
    func getSendTimes() -> [Date] { sendTimes }
}

enum TestError: Error {
    case networkError
}

// Test runner
print("🧪 Testing HTTPPipelineQueue - Swift TCP Pipeline")
print("================================================\n")

// Test 1: Basic Pipeline Flow
print("Test 1: Basic Pipeline Flow")
print("----------------------------")
let state1 = TestState()
await state1.addBatch(TestBatch(id: "batch-1", items: [1, 2, 3]))
await state1.addBatch(TestBatch(id: "batch-2", items: [4, 5, 6]))
await state1.addBatch(TestBatch(id: "batch-3", items: [7, 8, 9]))

let queue1 = HTTPPipelineQueue<TestBatch>(
    config: HTTPPipelineQueue.Configuration(
        maxInFlight: 3,
        pollIntervalMS: 50,
        requestTimeout: 1.0,
        maxRetries: 3,
        baseRetryDelaySeconds: 0.1,
        maxRetryDelaySeconds: 1.0
    ),
    getNextBatch: { await state1.getNext() },
    sendBatch: { batch in
        await state1.recordSend(batch)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
    },
    onSuccess: { batch in await state1.recordSuccess(batch.id) },
    onFailure: { batch, _ in await state1.recordFailure(batch.id) }
)

await queue1.start()
try await Task.sleep(nanoseconds: 500_000_000) // 500ms
await queue1.stop()

let successful1 = await state1.getSuccessful()
let sendCount1 = await state1.getSendCallCount()

print("  ✓ Sent: \(sendCount1) batches")
print("  ✓ Successful: \(successful1.count) batches")
print("  ✓ Order: \(successful1.joined(separator: ", "))")
assert(successful1.count == 3, "Expected 3 successful batches")
assert(successful1 == ["batch-1", "batch-2", "batch-3"], "Order should be maintained")
print("  ✅ PASSED\n")

// Test 2: Concurrent In-Flight Limit
print("Test 2: Concurrent In-Flight Limit")
print("-----------------------------------")
let state2 = TestState()
await state2.addBatch(TestBatch(id: "batch-1", items: [1]))
await state2.addBatch(TestBatch(id: "batch-2", items: [2]))
await state2.addBatch(TestBatch(id: "batch-3", items: [3]))
await state2.addBatch(TestBatch(id: "batch-4", items: [4]))

let queue2 = HTTPPipelineQueue<TestBatch>(
    config: HTTPPipelineQueue.Configuration(
        maxInFlight: 2,
        pollIntervalMS: 50,
        requestTimeout: 1.0,
        maxRetries: 3,
        baseRetryDelaySeconds: 0.1,
        maxRetryDelaySeconds: 1.0
    ),
    getNextBatch: { await state2.getNext() },
    sendBatch: { batch in
        await state2.recordSend(batch)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    },
    onSuccess: { batch in await state2.recordSuccess(batch.id) },
    onFailure: { batch, _ in await state2.recordFailure(batch.id) }
)

await queue2.start()
try await Task.sleep(nanoseconds: 150_000_000) // 150ms
let inFlight = await queue2.getInFlightCount()
print("  ✓ In-flight count after 150ms: \(inFlight)")
assert(inFlight <= 2, "In-flight should not exceed maxInFlight")

try await Task.sleep(nanoseconds: 500_000_000) // Wait for completion
await queue2.stop()

let successful2 = await state2.getSuccessful()
print("  ✓ All batches completed: \(successful2.count)")
assert(successful2.count == 4, "All 4 batches should complete")
print("  ✅ PASSED\n")

// Test 3: Retry Logic with Exponential Backoff
print("Test 3: Retry Logic with Exponential Backoff")
print("--------------------------------------------")
let state3 = TestState()
await state3.addBatch(TestBatch(id: "batch-1", items: [1]))
await state3.setShouldFail(true)

let queue3 = HTTPPipelineQueue<TestBatch>(
    config: HTTPPipelineQueue.Configuration(
        maxInFlight: 1,
        pollIntervalMS: 50,
        requestTimeout: 1.0,
        maxRetries: 3,
        baseRetryDelaySeconds: 0.1,
        maxRetryDelaySeconds: 1.0
    ),
    getNextBatch: { await state3.getNext() },
    sendBatch: { batch in
        await state3.recordSend(batch)
        await state3.incrementFailureCount()
        throw TestError.networkError
    },
    onSuccess: { batch in await state3.recordSuccess(batch.id) },
    onFailure: { batch, _ in await state3.recordFailure(batch.id) }
)

await queue3.start()
try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds for retries
await queue3.stop()

let failed = await state3.getFailed()
let failureCount = await state3.getFailureCount()
let sendTimes = await state3.getSendTimes()

print("  ✓ Failed batches: \(failed.count)")
print("  ✓ Total attempts: \(failureCount) (1 initial + 3 retries)")
assert(failed.count == 1, "Should have 1 failed batch")
assert(failureCount == 4, "Should have tried 4 times")

// Verify exponential backoff timing
if sendTimes.count >= 4 {
    let delay1 = sendTimes[1].timeIntervalSince(sendTimes[0])
    let delay2 = sendTimes[2].timeIntervalSince(sendTimes[1])
    let delay3 = sendTimes[3].timeIntervalSince(sendTimes[2])

    print("  ✓ Retry delays:")
    print("    - 1st retry: \(String(format: "%.3f", delay1))s (expected ~0.1s)")
    print("    - 2nd retry: \(String(format: "%.3f", delay2))s (expected ~0.2s)")
    print("    - 3rd retry: \(String(format: "%.3f", delay3))s (expected ~0.4s)")

    assert(delay1 >= 0.08, "First retry should be ~0.1s")
    assert(delay2 >= 0.15, "Second retry should be ~0.2s")
    assert(delay3 >= 0.3, "Third retry should be ~0.4s")
}
print("  ✅ PASSED\n")

// Test 4: High Throughput
print("Test 4: High Throughput")
print("-----------------------")
let state4 = TestState()
for i in 1...50 {
    await state4.addBatch(TestBatch(id: "batch-\(i)", items: [i]))
}

let startTime = Date()
let queue4 = HTTPPipelineQueue<TestBatch>(
    config: HTTPPipelineQueue.Configuration(
        maxInFlight: 10,        // Increased concurrency
        pollIntervalMS: 10,     // Faster polling
        requestTimeout: 1.0,
        maxRetries: 2,
        baseRetryDelaySeconds: 0.1,
        maxRetryDelaySeconds: 1.0
    ),
    getNextBatch: { await state4.getNext() },
    sendBatch: { batch in
        await state4.recordSend(batch)
        try await Task.sleep(nanoseconds: 2_000_000) // 2ms (more realistic)
    },
    onSuccess: { batch in await state4.recordSuccess(batch.id) },
    onFailure: { batch, _ in await state4.recordFailure(batch.id) }
)

await queue4.start()

// Wait for all batches to complete with timeout
var completed = false
for _ in 0..<50 {  // Check every 100ms, max 5 seconds
    try await Task.sleep(nanoseconds: 100_000_000)
    let count = await state4.getSuccessful().count
    if count == 50 {
        completed = true
        break
    }
}

await queue4.stop()

let duration = Date().timeIntervalSince(startTime)
let successful4 = await state4.getSuccessful()

print("  ✓ Processed: \(successful4.count) batches")
print("  ✓ Duration: \(String(format: "%.3f", duration))s")
if successful4.count > 0 {
    print("  ✓ Throughput: \(String(format: "%.0f", Double(successful4.count) / duration)) batches/sec")
}
assert(successful4.count == 50, "Should process all 50 batches")
assert(completed, "Should complete processing within timeout")
print("  ✅ PASSED\n")

// Test 5: Empty Queue
print("Test 5: Empty Queue Handling")
print("-----------------------------")
let state5 = TestState()

let queue5 = HTTPPipelineQueue<TestBatch>(
    config: HTTPPipelineQueue.Configuration.default(),
    getNextBatch: { await state5.getNext() },
    sendBatch: { batch in await state5.recordSend(batch) },
    onSuccess: { batch in await state5.recordSuccess(batch.id) },
    onFailure: { batch, _ in await state5.recordFailure(batch.id) }
)

await queue5.start()
try await Task.sleep(nanoseconds: 200_000_000) // 200ms
await queue5.stop()

let sendCount5 = await state5.getSendCallCount()
print("  ✓ Batches sent: \(sendCount5)")
assert(sendCount5 == 0, "Should not send any batches")
print("  ✅ PASSED\n")

// Summary
print("================================================")
print("🎉 ALL TESTS PASSED!")
print("================================================")
print("\n✅ HTTPPipelineQueue Swift TCP Pipeline is working correctly!")
print("\nTest Summary:")
print("  ✓ Basic pipeline flow")
print("  ✓ Concurrent in-flight limit enforcement")
print("  ✓ Retry logic with exponential backoff")
print("  ✓ High throughput (50 batches)")
print("  ✓ Empty queue handling")
print("\nReady for production! 🚀")
