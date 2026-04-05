//
//  StreamingParser.swift
//  unbound-macos
//
//  Generic streaming parser for line-based content.
//  Maintains buffer state across multiple chunks.
//

import Foundation

/// Generic streaming parser that processes chunks of text line-by-line
class StreamingParser<Output> {
    private var buffer: String = ""

    // MARK: - Abstract Methods (Override in Subclass)

    /// Process a single line and return parsed output
    /// - Parameter line: Line to process (without trailing newline)
    /// - Returns: Parsed output or nil if line should be skipped
    func processLine(_ line: String) -> Output? {
        fatalError("processLine must be overridden in subclass")
    }

    /// Finalize parsing and return any remaining output
    /// Called when stream ends to flush buffer
    /// - Returns: Any remaining parsed output
    func finalizeBuffer() -> [Output] {
        fatalError("finalizeBuffer must be overridden in subclass")
    }

    // MARK: - Public Interface

    /// Parse a chunk of streaming data
    /// - Parameter chunk: Text chunk to parse
    /// - Returns: Array of parsed outputs
    func parse(_ chunk: String) -> [Output] {
        buffer += chunk
        var results: [Output] = []

        // Process buffer line by line
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])

            if let output = processLine(line) {
                results.append(output)
            }
        }

        return results
    }

    /// Finalize parsing and return any remaining content
    /// - Returns: Array of parsed outputs from remaining buffer
    func finalize() -> [Output] {
        var results: [Output] = []

        // Process remaining buffer
        if !buffer.isEmpty {
            if let output = processLine(buffer) {
                results.append(output)
            }
            buffer = ""
        }

        // Allow subclass to finalize
        results.append(contentsOf: finalizeBuffer())

        return results
    }

    /// Reset parser state
    func reset() {
        buffer = ""
    }

    /// Get current buffer content (for testing)
    var currentBuffer: String {
        buffer
    }
}
