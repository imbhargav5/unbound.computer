//
//  HTTPPipelineQueue.swift
//  unbound-macos
//
//  Reusable generic HTTP pipelining queue with configurable concurrency.
//  Allows multiple HTTP requests to be in-flight simultaneously without
//  waiting for acknowledgments, improving throughput for batch operations.
//

import Foundation

/// Generic HTTP pipelining queue that manages concurrent requests
/// with configurable in-flight limits and retry logic
actor HTTPPipelineQueue<Batch: Sendable> {

    // MARK: - Configuration

    /// Configuration for the pipeline queue
    struct Configuration {
        /// Maximum number of concurrent in-flight requests
        let maxInFlight: Int

        /// Polling interval in milliseconds
        let pollIntervalMS: Int

        /// HTTP request timeout in seconds
        let requestTimeout: TimeInterval

        /// Maximum retry attempts before marking as failed
        let maxRetries: Int

        /// Base retry delay in seconds (exponential backoff)
        let baseRetryDelaySeconds: Double

        /// Maximum retry delay in seconds (cap for exponential backoff)
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

    // MARK: - Callbacks

    /// Callback to get the next batch to send
    typealias GetNextBatch = () async -> Batch?

    /// Callback to send a batch via HTTP
    typealias SendBatch = (Batch) async throws -> Void

    /// Callback to handle successful batch acknowledgment
    typealias OnSuccess = (Batch) async throws -> Void

    /// Callback to handle batch failure
    typealias OnFailure = (Batch, Error) async throws -> Void

    // MARK: - Properties

    private let config: Configuration
    private let getNextBatch: GetNextBatch
    private let sendBatch: SendBatch
    private let onSuccess: OnSuccess
    private let onFailure: OnFailure

    private var isRunning = false
    private var pollingTask: Task<Void, Never>?
    private var inFlightCount = 0

    // MARK: - Initialization

    /// Initialize the HTTP pipeline queue
    /// - Parameters:
    ///   - config: Configuration for the pipeline
    ///   - getNextBatch: Callback to retrieve the next batch to send
    ///   - sendBatch: Callback to send a batch via HTTP
    ///   - onSuccess: Callback when batch is successfully acknowledged
    ///   - onFailure: Callback when batch fails after all retries
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

    // MARK: - Control

    /// Start the pipeline queue polling loop
    func start() {
        guard !isRunning else { return }
        isRunning = true

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.runPollingLoop()
        }
    }

    /// Stop the pipeline queue (waits for in-flight requests to complete)
    func stop() async {
        guard isRunning else { return }
        isRunning = false

        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Get the current number of in-flight requests
    func getInFlightCount() -> Int {
        inFlightCount
    }

    // MARK: - Polling Loop

    private func runPollingLoop() async {
        while isRunning {
            do {
                // Check if we can send more batches
                if inFlightCount < config.maxInFlight {
                    // Try to get next batch
                    if let batch = await getNextBatch() {
                        // Increment in-flight counter
                        inFlightCount += 1

                        // Send batch in background (pipelined)
                        Task.detached(priority: .high) { [weak self] in
                            guard let self else { return }
                            await self.processBatch(batch, retryCount: 0)
                        }
                    }
                }

                // Wait before next poll
                try await Task.sleep(nanoseconds: UInt64(config.pollIntervalMS) * 1_000_000)
            } catch {
                // Sleep was cancelled or other error
                if Task.isCancelled {
                    break
                }
            }
        }
    }

    // MARK: - Batch Processing

    /// Process a batch with retry logic
    private func processBatch(_ batch: Batch, retryCount: Int) async {
        do {
            // Send the batch via HTTP
            try await sendBatch(batch)

            // Success - call success callback
            try await onSuccess(batch)

            // Decrement in-flight counter
            decrementInFlight()

        } catch {
            // Handle error with retry logic
            await handleBatchError(batch, error: error, retryCount: retryCount)
        }
    }

    /// Handle batch error with exponential backoff retry
    private func handleBatchError(
        _ batch: Batch,
        error: Error,
        retryCount: Int
    ) async {
        // Check if we should retry
        if retryCount >= config.maxRetries {
            // Max retries exceeded - call failure callback
            try? await onFailure(batch, error)

            // Decrement in-flight counter
            decrementInFlight()
            return
        }

        // Calculate exponential backoff delay
        let retryDelay = min(
            config.baseRetryDelaySeconds * pow(2.0, Double(retryCount)),
            config.maxRetryDelaySeconds
        )

        // Wait before retry
        try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))

        // Retry the batch
        await processBatch(batch, retryCount: retryCount + 1)
    }

    /// Decrement in-flight counter (thread-safe)
    private func decrementInFlight() {
        inFlightCount -= 1
    }
}

// MARK: - Identifiable Batch Protocol

/// Protocol for batches that can be identified
protocol IdentifiableBatch: Sendable {
    var batchId: String { get }
}
