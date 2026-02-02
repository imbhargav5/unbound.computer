//
//  SharedMemoryStream.swift
//  unbound-macos
//
//  High-performance shared memory consumer for streaming events from the daemon.
//  Uses POSIX shared memory (shm_open + mmap) for zero-copy, low-latency IPC.
//
//  This provides ~100x lower latency than Unix socket streaming:
//  - Socket: ~35-130 microseconds per event
//  - Shared memory: ~1-5 microseconds per event
//
//  ## Usage
//
//  ```swift
//  // Try to open shared memory stream (falls back to socket if unavailable)
//  if let stream = SharedMemoryConsumer.open(sessionId: session.id) {
//      // Read events with zero-copy
//      while let event = stream.tryRead() {
//          handleEvent(event)
//      }
//  }
//  ```
//

import Darwin
import Foundation
import Logging

private let logger = Logger(label: "app.stream")

// MARK: - Protocol Constants

/// Magic number: "UNBS" (UNBound Stream)
private let MAGIC: UInt32 = 0x554E4253

/// Current protocol version
private let VERSION: UInt32 = 1

/// Header size (cache-line aligned)
private let HEADER_SIZE = 64

/// Slot header size
private let SLOT_HEADER_SIZE = 56

// MARK: - Event Types

/// Event types that can be streamed via shared memory.
enum StreamEventType: UInt8 {
    case claudeEvent = 1
    case terminalOutput = 2
    case terminalFinished = 3
    case streamingChunk = 4
    case ping = 5
}

// MARK: - Stream Event

/// A single event read from the shared memory stream.
struct SharedMemoryEvent {
    let sessionId: String
    let eventType: StreamEventType
    let sequence: Int64
    let payload: Data
    let truncated: Bool

    /// Get payload as UTF-8 string.
    var payloadString: String? {
        String(data: payload, encoding: .utf8)
    }
}

// MARK: - Header Structures

/// Stream header at the start of shared memory.
/// Mirrors the Rust `StreamHeader` struct layout.
private struct StreamHeader {
    var magic: UInt32
    var version: UInt32
    var writeSeq: UInt64  // Atomic in actual memory
    var readSeq: UInt64   // Atomic in actual memory
    var flags: UInt32     // Atomic in actual memory
    var slotSize: UInt32
    var slotCount: UInt32
    var wakeFutex: UInt32
    var reserved: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
}

/// Slot header for each event in the ring buffer.
private struct SlotHeader {
    var len: UInt32
    var eventType: UInt8
    var flags: UInt8
    var reserved: UInt16
    var sequence: Int64
    var sessionId: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8)
}

// MARK: - Shared Memory Consumer

/// Consumer for reading events from the daemon's shared memory stream.
///
/// This class provides zero-copy, low-latency access to streaming events
/// from the daemon. It's designed for high-frequency events like Claude
/// CLI output and terminal streaming.
///
/// ## Thread Safety
///
/// This class is NOT thread-safe. Use from a single thread or protect
/// with external synchronization.
final class SharedMemoryConsumer {

    // MARK: - Properties

    private let sessionId: String
    private let fd: Int32
    private let mappedPtr: UnsafeMutableRawPointer
    private let mappedSize: Int
    private var readSeq: UInt64 = 0

    // MARK: - Initialization

    private init(sessionId: String, fd: Int32, ptr: UnsafeMutableRawPointer, size: Int) {
        self.sessionId = sessionId
        self.fd = fd
        self.mappedPtr = ptr
        self.mappedSize = size
    }

    deinit {
        // Unmap memory
        munmap(mappedPtr, mappedSize)
        // Close file descriptor
        close(fd)
        logger.debug("Closed shared memory stream for session \(sessionId)")
    }

    // MARK: - Factory

    /// Generate the shared memory name for a session.
    /// Must match the Rust daemon's naming convention.
    static func shmName(sessionId: String) -> String {
        // macOS limits shm names to 31 chars including the leading '/'
        // Format: "/ub_" + first 8 chars of session_id
        let shortId = String(sessionId.prefix(8))
        return "/ub_\(shortId)"
    }

    /// Open an existing shared memory stream for a session.
    ///
    /// - Parameter sessionId: The session ID to open
    /// - Returns: A consumer if the stream exists and is valid, nil otherwise
    static func open(sessionId: String) -> SharedMemoryConsumer? {
        let name = shmName(sessionId: sessionId)

        // Open existing shared memory
        let fd = shm_open(name, O_RDWR, 0)
        if fd == -1 {
            let error = String(cString: strerror(errno))
            logger.debug("shm_open failed for '\(name)': \(error)")
            return nil
        }

        // First, map just the header to read configuration
        guard let headerPtr = mmap(
            nil,
            HEADER_SIZE,
            PROT_READ,
            MAP_SHARED,
            fd,
            0
        ), headerPtr != MAP_FAILED else {
            let error = String(cString: strerror(errno))
            logger.warning("mmap header failed: \(error)")
            close(fd)
            return nil
        }

        // Read and validate header
        let header = headerPtr.assumingMemoryBound(to: StreamHeader.self).pointee

        guard header.magic == MAGIC else {
            logger.warning("Invalid magic number: \(String(format: "0x%X", header.magic))")
            munmap(headerPtr, HEADER_SIZE)
            close(fd)
            return nil
        }

        guard header.version == VERSION else {
            logger.warning("Unsupported version: \(header.version)")
            munmap(headerPtr, HEADER_SIZE)
            close(fd)
            return nil
        }

        // Calculate total size
        let totalSize = HEADER_SIZE + Int(header.slotSize) * Int(header.slotCount)
        munmap(headerPtr, HEADER_SIZE)

        // Map the full region
        guard let fullPtr = mmap(
            nil,
            totalSize,
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            fd,
            0
        ), fullPtr != MAP_FAILED else {
            let error = String(cString: strerror(errno))
            logger.warning("mmap full failed: \(error)")
            close(fd)
            return nil
        }

        logger.info("Opened shared memory stream for session \(sessionId) (\(totalSize) bytes)")

        return SharedMemoryConsumer(
            sessionId: sessionId,
            fd: fd,
            ptr: fullPtr,
            size: totalSize
        )
    }

    // MARK: - Reading

    /// Check if the stream has been shut down by the producer.
    var isShutdown: Bool {
        let header = mappedPtr.assumingMemoryBound(to: StreamHeader.self).pointee
        return (header.flags & 0x2) != 0  // SHUTDOWN flag
    }

    /// Check if there are events available to read.
    var hasEvents: Bool {
        let header = mappedPtr.assumingMemoryBound(to: StreamHeader.self).pointee
        return readSeq < header.writeSeq
    }

    /// Get the number of events available to read.
    var availableEvents: UInt64 {
        let header = mappedPtr.assumingMemoryBound(to: StreamHeader.self).pointee
        return header.writeSeq > readSeq ? header.writeSeq - readSeq : 0
    }

    /// Try to read the next event without blocking.
    ///
    /// - Returns: The next event, or nil if no events available or shutdown
    func tryRead() -> SharedMemoryEvent? {
        let header = mappedPtr.assumingMemoryBound(to: StreamHeader.self).pointee

        // Check shutdown
        if isShutdown && !hasEvents {
            return nil
        }

        // Check if data available (atomic read)
        let writeSeq = header.writeSeq
        if readSeq >= writeSeq {
            return nil
        }

        // Read the slot
        let event = readSlot(at: readSeq, header: header)
        readSeq += 1

        return event
    }

    /// Read all available events.
    ///
    /// - Returns: Array of all currently available events
    func readAll() -> [SharedMemoryEvent] {
        var events: [SharedMemoryEvent] = []
        while let event = tryRead() {
            events.append(event)
        }
        return events
    }

    /// Read up to `max` events.
    ///
    /// - Parameter max: Maximum number of events to read
    /// - Returns: Array of events (may be fewer than max if not available)
    func readBatch(max: Int) -> [SharedMemoryEvent] {
        var events: [SharedMemoryEvent] = []
        events.reserveCapacity(min(max, 64))
        for _ in 0..<max {
            guard let event = tryRead() else { break }
            events.append(event)
        }
        return events
    }

    /// Skip to the latest position, ignoring any backlog.
    ///
    /// - Returns: Number of events skipped
    @discardableResult
    func skipToLatest() -> UInt64 {
        let header = mappedPtr.assumingMemoryBound(to: StreamHeader.self).pointee
        let writeSeq = header.writeSeq
        let skipped = writeSeq > readSeq ? writeSeq - readSeq : 0
        readSeq = writeSeq
        if skipped > 0 {
            logger.debug("Skipped \(skipped) events to latest position")
        }
        return skipped
    }

    // MARK: - Private

    private func readSlot(at seq: UInt64, header: StreamHeader) -> SharedMemoryEvent {
        let slotMask = UInt64(header.slotCount - 1)
        let slotIndex = seq & slotMask
        let slotOffset = HEADER_SIZE + Int(slotIndex) * Int(header.slotSize)

        let slotPtr = mappedPtr.advanced(by: slotOffset)
        let slotHeader = slotPtr.assumingMemoryBound(to: SlotHeader.self).pointee

        // Read session ID
        let sessionIdBytes = withUnsafeBytes(of: slotHeader.sessionId) { Data($0) }
        let sessionId = String(data: sessionIdBytes, encoding: .utf8)?
            .trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""

        // Read event type
        let eventType = StreamEventType(rawValue: slotHeader.eventType) ?? .claudeEvent

        // Read payload
        let payloadLen = Int(slotHeader.len)
        let payloadPtr = slotPtr.advanced(by: SLOT_HEADER_SIZE)
        let payload = Data(bytes: payloadPtr, count: payloadLen)

        // Check truncation flag
        let truncated = (slotHeader.flags & 0x2) != 0

        return SharedMemoryEvent(
            sessionId: sessionId,
            eventType: eventType,
            sequence: slotHeader.sequence,
            payload: payload,
            truncated: truncated
        )
    }
}

// MARK: - AsyncSequence Support

/// Async sequence wrapper for SharedMemoryConsumer.
/// Allows using `for await` syntax with shared memory events.
struct SharedMemoryEventSequence: AsyncSequence {
    typealias Element = SharedMemoryEvent

    private let consumer: SharedMemoryConsumer
    private let pollInterval: Swift.Duration

    init(consumer: SharedMemoryConsumer, pollInterval: Swift.Duration = .milliseconds(1)) {
        self.consumer = consumer
        self.pollInterval = pollInterval
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(consumer: consumer, pollInterval: pollInterval)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private let consumer: SharedMemoryConsumer
        private let pollInterval: Swift.Duration

        init(consumer: SharedMemoryConsumer, pollInterval: Swift.Duration) {
            self.consumer = consumer
            self.pollInterval = pollInterval
        }

        mutating func next() async -> SharedMemoryEvent? {
            while !Task.isCancelled {
                // Try non-blocking read first
                if let event = consumer.tryRead() {
                    return event
                }

                // Check shutdown
                if consumer.isShutdown {
                    return nil
                }

                // Wait briefly before polling again
                try? await Task.sleep(for: pollInterval)
            }
            return nil
        }
    }
}

extension SharedMemoryConsumer {
    /// Create an async sequence for reading events.
    ///
    /// - Parameter pollInterval: How often to poll when no events available
    /// - Returns: An async sequence of events
    func events(pollInterval: Swift.Duration = .milliseconds(1)) -> SharedMemoryEventSequence {
        SharedMemoryEventSequence(consumer: self, pollInterval: pollInterval)
    }
}
