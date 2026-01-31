//! Error types for daemon-stream.

use thiserror::Error;

/// Errors that can occur during stream operations.
#[derive(Error, Debug)]
pub enum StreamError {
    /// Failed to create or open shared memory
    #[error("shared memory error: {0}")]
    SharedMemory(String),

    /// Failed to map shared memory into address space
    #[error("memory mapping error: {0}")]
    Mmap(String),

    /// Invalid shared memory header (wrong magic or version)
    #[error("invalid stream header: {0}")]
    InvalidHeader(String),

    /// Ring buffer is full (producer would overwrite unread data)
    #[error("ring buffer full, consumer lagging")]
    BufferFull,

    /// Stream has been shut down
    #[error("stream has been shut down")]
    Shutdown,

    /// Payload too large for slot
    #[error("payload too large: {size} bytes, max {max} bytes")]
    PayloadTooLarge { size: usize, max: usize },

    /// Invalid session ID format
    #[error("invalid session ID: expected 36-character UUID")]
    InvalidSessionId,

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Platform-specific error
    #[error("platform error: {0}")]
    Platform(String),
}

/// Result type for stream operations.
pub type StreamResult<T> = Result<T, StreamError>;
