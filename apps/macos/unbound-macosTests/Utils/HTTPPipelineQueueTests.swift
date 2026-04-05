//
//  HTTPPipelineQueueTests.swift
//  unbound-macosTests
//
//  Unit tests for HTTPPipelineQueue with mocked HTTP operations.
//

import XCTest
@testable import unbound_macos

final class HTTPPipelineQueueTests: XCTestCase {

    // MARK: - Test Models

    struct TestBatch: Sendable, IdentifiableBatch {
        let batchId: String
        let items: [Int]
    }

    // MARK: - Test State

    actor TestState {
        var batches: [TestBatch] = []
        var sentBatches: [String: TestBatch] = [:]
        var successfulBatches: [String] = []
        var failedBatches: [String] = []
        var sendCallCount = 0
        var shouldFail = false
        var failureCount = 0

        func addBatch(_ batch: TestBatch) {
            batches.append(batch)
        }

        func getNextBatch() -> TestBatch? {
            guard !batches.isEmpty else { return nil }
            return batches.removeFirst()
        }

        func recordSend(_ batch: TestBatch) {
            sentBatches[batch.batchId] = batch
            sendCallCount += 1
        }

        func recordSuccess(_ batch: TestBatch) {
            successfulBatches.append(batch.batchId)
        }

        func recordFailure(_ batch: TestBatch) {
            failedBatches.append(batch.batchId)
        }

        func setShouldFail(_ shouldFail: Bool) {
            self.shouldFail = shouldFail
        }

        func incrementFailureCount() {
            failureCount += 1
        }

        func getSendCallCount() -> Int {
            sendCallCount
        }

        func getSuccessfulBatches() -> [String] {
            successfulBatches
        }

        func getFailedBatches() -> [String] {
            failedBatches
        }

        func getFailureCount() -> Int {
            failureCount
        }
    }

    // MARK: - Tests

    func testBasicPipelineFlow() async throws {
        // Given: A pipeline queue with 3 batches
        let state = TestState()
        await state.addBatch(TestBatch(batchId: "batch-1", items: [1, 2, 3]))
        await state.addBatch(TestBatch(batchId: "batch-2", items: [4, 5, 6]))
        await state.addBatch(TestBatch(batchId: "batch-3", items: [7, 8, 9]))

        let expectation = expectation(description: "All batches processed")
        expectation.expectedFulfillmentCount = 3

        let queue = HTTPPipelineQueue<TestBatch>(
            config: HTTPPipelineQueue.Configuration(
                maxInFlight: 3,
                pollIntervalMS: 50,
                requestTimeout: 1.0,
                maxRetries: 3,
                baseRetryDelaySeconds: 0.1,
                maxRetryDelaySeconds: 1.0
            ),
            getNextBatch: {
                await state.getNextBatch()
            },
            sendBatch: { batch in
                await state.recordSend(batch)
                // Simulate network delay
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            },
            onSuccess: { batch in
                await state.recordSuccess(batch)
                expectation.fulfill()
            },
            onFailure: { batch, _ in
                await state.recordFailure(batch)
            }
        )

        // When: Start the queue
        await queue.start()

        // Then: All batches should be processed successfully
        await fulfillment(of: [expectation], timeout: 2.0)

        await queue.stop()

        let successful = await state.getSuccessfulBatches()
        XCTAssertEqual(successful.count, 3, "Should have 3 successful batches")
        XCTAssertTrue(successful.contains("batch-1"), "batch-1 should be successful")
        XCTAssertTrue(successful.contains("batch-2"), "batch-2 should be successful")
        XCTAssertTrue(successful.contains("batch-3"), "batch-3 should be successful")

        let sendCount = await state.getSendCallCount()
        XCTAssertEqual(sendCount, 3, "Should have sent 3 batches")
    }

    func testConcurrentInFlightLimit() async throws {
        // Given: A pipeline queue with max 2 in-flight
        let state = TestState()
        await state.addBatch(TestBatch(batchId: "batch-1", items: [1]))
        await state.addBatch(TestBatch(batchId: "batch-2", items: [2]))
        await state.addBatch(TestBatch(batchId: "batch-3", items: [3]))

        let expectation = expectation(description: "All batches processed")
        expectation.expectedFulfillmentCount = 3

        let queue = HTTPPipelineQueue<TestBatch>(
            config: HTTPPipelineQueue.Configuration(
                maxInFlight: 2, // Only 2 concurrent requests
                pollIntervalMS: 50,
                requestTimeout: 1.0,
                maxRetries: 3,
                baseRetryDelaySeconds: 0.1,
                maxRetryDelaySeconds: 1.0
            ),
            getNextBatch: {
                await state.getNextBatch()
            },
            sendBatch: { batch in
                await state.recordSend(batch)
                // Simulate longer network delay to test concurrency limit
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            },
            onSuccess: { batch in
                await state.recordSuccess(batch)
                expectation.fulfill()
            },
            onFailure: { batch, _ in
                await state.recordFailure(batch)
            }
        )

        // When: Start the queue
        await queue.start()

        // Check in-flight count after a short delay
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        let inFlightCount = await queue.getInFlightCount()

        // Then: In-flight count should not exceed 2
        XCTAssertLessThanOrEqual(inFlightCount, 2, "In-flight count should not exceed maxInFlight")

        await fulfillment(of: [expectation], timeout: 2.0)
        await queue.stop()

        let successful = await state.getSuccessfulBatches()
        XCTAssertEqual(successful.count, 3, "Should have 3 successful batches")
    }

    func testRetryLogicOnFailure() async throws {
        // Given: A pipeline queue with retries enabled and a failing batch
        let state = TestState()
        await state.addBatch(TestBatch(batchId: "batch-1", items: [1]))
        await state.setShouldFail(true)

        let expectation = expectation(description: "Batch should fail after retries")

        let queue = HTTPPipelineQueue<TestBatch>(
            config: HTTPPipelineQueue.Configuration(
                maxInFlight: 1,
                pollIntervalMS: 50,
                requestTimeout: 1.0,
                maxRetries: 3, // Allow 3 retries
                baseRetryDelaySeconds: 0.05, // Short delay for testing
                maxRetryDelaySeconds: 0.2
            ),
            getNextBatch: {
                await state.getNextBatch()
            },
            sendBatch: { batch in
                await state.recordSend(batch)
                await state.incrementFailureCount()
                // Simulate failure
                throw TestError.networkError
            },
            onSuccess: { batch in
                await state.recordSuccess(batch)
            },
            onFailure: { batch, _ in
                await state.recordFailure(batch)
                expectation.fulfill()
            }
        )

        // When: Start the queue
        await queue.start()

        // Then: Batch should fail after retries
        await fulfillment(of: [expectation], timeout: 3.0)
        await queue.stop()

        let failed = await state.getFailedBatches()
        XCTAssertEqual(failed.count, 1, "Should have 1 failed batch")
        XCTAssertEqual(failed.first, "batch-1", "batch-1 should have failed")

        // Should have tried 1 initial + 3 retries = 4 total attempts
        let failureCount = await state.getFailureCount()
        XCTAssertEqual(failureCount, 4, "Should have attempted 4 times (1 initial + 3 retries)")
    }

    func testExponentialBackoff() async throws {
        // Given: A pipeline queue with exponential backoff
        let state = TestState()
        await state.addBatch(TestBatch(batchId: "batch-1", items: [1]))
        await state.setShouldFail(true)

        let expectation = expectation(description: "Batch should fail after retries")

        var attemptTimes: [Date] = []
        let queue = HTTPPipelineQueue<TestBatch>(
            config: HTTPPipelineQueue.Configuration(
                maxInFlight: 1,
                pollIntervalMS: 50,
                requestTimeout: 1.0,
                maxRetries: 3,
                baseRetryDelaySeconds: 0.1, // 100ms base delay
                maxRetryDelaySeconds: 1.0
            ),
            getNextBatch: {
                await state.getNextBatch()
            },
            sendBatch: { batch in
                attemptTimes.append(Date())
                await state.recordSend(batch)
                throw TestError.networkError
            },
            onSuccess: { batch in
                await state.recordSuccess(batch)
            },
            onFailure: { batch, _ in
                await state.recordFailure(batch)
                expectation.fulfill()
            }
        )

        // When: Start the queue
        await queue.start()

        // Then: Verify exponential backoff timing
        await fulfillment(of: [expectation], timeout: 3.0)
        await queue.stop()

        XCTAssertEqual(attemptTimes.count, 4, "Should have 4 attempts")

        if attemptTimes.count == 4 {
            // Check delays between attempts (with tolerance for execution time)
            let delay1 = attemptTimes[1].timeIntervalSince(attemptTimes[0])
            let delay2 = attemptTimes[2].timeIntervalSince(attemptTimes[1])
            let delay3 = attemptTimes[3].timeIntervalSince(attemptTimes[2])

            // Exponential backoff: 0.1s, 0.2s, 0.4s
            XCTAssertGreaterThan(delay1, 0.08, "First retry delay should be ~0.1s")
            XCTAssertGreaterThan(delay2, 0.15, "Second retry delay should be ~0.2s")
            XCTAssertGreaterThan(delay3, 0.3, "Third retry delay should be ~0.4s")
        }
    }

    func testStopWaitsForInFlight() async throws {
        // Given: A pipeline queue with an in-flight request
        let state = TestState()
        await state.addBatch(TestBatch(batchId: "batch-1", items: [1]))

        let sendStarted = expectation(description: "Send started")
        let sendCompleted = expectation(description: "Send completed")

        let queue = HTTPPipelineQueue<TestBatch>(
            config: HTTPPipelineQueue.Configuration(
                maxInFlight: 1,
                pollIntervalMS: 50,
                requestTimeout: 1.0,
                maxRetries: 0,
                baseRetryDelaySeconds: 0.1,
                maxRetryDelaySeconds: 1.0
            ),
            getNextBatch: {
                await state.getNextBatch()
            },
            sendBatch: { batch in
                sendStarted.fulfill()
                await state.recordSend(batch)
                // Simulate long network request
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            },
            onSuccess: { batch in
                await state.recordSuccess(batch)
                sendCompleted.fulfill()
            },
            onFailure: { batch, _ in
                await state.recordFailure(batch)
            }
        )

        // When: Start the queue and immediately stop after send starts
        await queue.start()
        await fulfillment(of: [sendStarted], timeout: 1.0)

        // Stop should wait for in-flight to complete
        await queue.stop()

        // Then: Send should have completed
        await fulfillment(of: [sendCompleted], timeout: 1.0)

        let successful = await state.getSuccessfulBatches()
        XCTAssertEqual(successful.count, 1, "In-flight batch should have completed")
    }

    func testEmptyQueueDoesNothing() async throws {
        // Given: A pipeline queue with no batches
        let state = TestState()

        let queue = HTTPPipelineQueue<TestBatch>(
            config: HTTPPipelineQueue.Configuration.default(),
            getNextBatch: {
                await state.getNextBatch()
            },
            sendBatch: { batch in
                await state.recordSend(batch)
            },
            onSuccess: { batch in
                await state.recordSuccess(batch)
            },
            onFailure: { batch, _ in
                await state.recordFailure(batch)
            }
        )

        // When: Start and run for a short time
        await queue.start()
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        await queue.stop()

        // Then: No batches should be processed
        let sendCount = await state.getSendCallCount()
        XCTAssertEqual(sendCount, 0, "Should not have sent any batches")
    }

    func testHighThroughputMultipleBatches() async throws {
        // Given: A pipeline queue with many batches
        let state = TestState()
        let batchCount = 20

        for i in 1...batchCount {
            await state.addBatch(TestBatch(batchId: "batch-\(i)", items: [i]))
        }

        let expectation = expectation(description: "All batches processed")
        expectation.expectedFulfillmentCount = batchCount

        let queue = HTTPPipelineQueue<TestBatch>(
            config: HTTPPipelineQueue.Configuration(
                maxInFlight: 5, // Higher concurrency
                pollIntervalMS: 20, // Faster polling
                requestTimeout: 1.0,
                maxRetries: 2,
                baseRetryDelaySeconds: 0.1,
                maxRetryDelaySeconds: 1.0
            ),
            getNextBatch: {
                await state.getNextBatch()
            },
            sendBatch: { batch in
                await state.recordSend(batch)
                // Simulate fast network
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            },
            onSuccess: { batch in
                await state.recordSuccess(batch)
                expectation.fulfill()
            },
            onFailure: { batch, _ in
                await state.recordFailure(batch)
            }
        )

        // When: Start the queue
        let startTime = Date()
        await queue.start()

        // Then: All batches should be processed quickly
        await fulfillment(of: [expectation], timeout: 5.0)
        await queue.stop()

        let duration = Date().timeIntervalSince(startTime)
        let successful = await state.getSuccessfulBatches()

        XCTAssertEqual(successful.count, batchCount, "Should have processed all batches")

        // With 5 concurrent requests and 5ms per request, theoretical min time is ~20ms
        // Allow up to 2 seconds for overhead and polling
        XCTAssertLessThan(duration, 2.0, "Should process 20 batches quickly with pipelining")
    }
}

// MARK: - Test Errors

enum TestError: Error {
    case networkError
    case timeoutError
}
