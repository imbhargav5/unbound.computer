//! Windows shared memory implementation (STUB).
//!
//! # Implementation Status: NOT YET IMPLEMENTED
//!
//! This module contains stubs for the Windows implementation of shared memory
//! streaming. The actual implementation will be added later.
//!
//! # Platform Decision Documentation
//!
//! ## Why Platform-Specific Implementations?
//!
//! We chose to use platform-specific shared memory APIs rather than a
//! cross-platform abstraction for several reasons:
//!
//! 1. **Performance**: Native APIs provide the best performance. Windows named
//!    shared memory and events are highly optimized by the kernel.
//!
//! 2. **Semantics**: POSIX `shm_open` and Windows `CreateFileMapping` have
//!    different semantics around naming, permissions, and lifecycle.
//!
//! 3. **Signaling**: Linux has futex, macOS has dispatch_semaphore/mach_port,
//!    and Windows has Event objects. These don't map cleanly to each other.
//!
//! 4. **Sandboxing**: Each platform has different sandboxing considerations
//!    that affect how shared memory can be accessed.
//!
//! ## Windows Implementation Plan
//!
//! When implementing Windows support, use:
//!
//! ### Shared Memory
//!
//! ```ignore
//! use windows::Win32::System::Memory::*;
//!
//! // Create named shared memory
//! let mapping = CreateFileMappingW(
//!     INVALID_HANDLE_VALUE,  // Use paging file
//!     None,                   // Default security
//!     PAGE_READWRITE,
//!     (size >> 32) as u32,
//!     size as u32,
//!     &HSTRING::from(format!("Local\\unbound_stream_{}", session_id)),
//! )?;
//!
//! // Map into address space
//! let view = MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, size);
//! ```
//!
//! ### Event Signaling
//!
//! ```ignore
//! use windows::Win32::System::Threading::*;
//!
//! // Create auto-reset event for consumer wakeup
//! let event = CreateEventW(
//!     None,
//!     false,  // Auto-reset
//!     false,  // Initial state: non-signaled
//!     &HSTRING::from(format!("Local\\unbound_event_{}", session_id)),
//! )?;
//!
//! // Producer signals after writing
//! SetEvent(event);
//!
//! // Consumer waits for data
//! WaitForSingleObject(event, timeout_ms);
//! ```
//!
//! ### Naming Convention
//!
//! Windows shared memory names should use the `Local\` prefix for per-session
//! objects. The format will be:
//!
//! - Shared memory: `Local\unbound_stream_{session_id}`
//! - Wake event: `Local\unbound_event_{session_id}`
//!
//! The `Local\` prefix creates the object in the session namespace, which is
//! appropriate for a per-user daemon.
//!
//! ### Security Considerations
//!
//! 1. Use explicit security descriptors if the daemon runs as a service
//! 2. Consider using `Global\` prefix if cross-session access is needed
//! 3. Handle `ERROR_ALREADY_EXISTS` when opening existing objects
//!
//! ### Client Implementation (C#)
//!
//! The .NET Framework has excellent built-in support for memory-mapped files:
//!
//! ```csharp
//! // C# client implementation sketch
//! using System.IO.MemoryMappedFiles;
//! using System.Threading;
//!
//! public class StreamConsumer : IDisposable
//! {
//!     private readonly MemoryMappedFile _mmf;
//!     private readonly MemoryMappedViewAccessor _view;
//!     private readonly EventWaitHandle _event;
//!
//!     public StreamConsumer(string sessionId)
//!     {
//!         _mmf = MemoryMappedFile.OpenExisting($"Local\\unbound_stream_{sessionId}");
//!         _view = _mmf.CreateViewAccessor();
//!         _event = EventWaitHandle.OpenExisting($"Local\\unbound_event_{sessionId}");
//!     }
//!
//!     public StreamEvent? TryRead()
//!     {
//!         // Read directly from mapped memory - zero copy!
//!         var writeSeq = _view.ReadUInt64(8);  // Offset of write_seq in header
//!         // ... implement ring buffer reading
//!     }
//!
//!     public async Task<StreamEvent?> ReadAsync(CancellationToken ct)
//!     {
//!         while (!ct.IsCancellationRequested)
//!         {
//!             if (TryRead() is StreamEvent e) return e;
//!             await Task.Run(() => _event.WaitOne(100), ct);
//!         }
//!         return null;
//!     }
//! }
//! ```
//!
//! ## Fallback Strategy
//!
//! Until Windows support is implemented, Windows clients should:
//!
//! 1. Use the existing Unix socket implementation (works via Windows Subsystem
//!    for Linux or named pipes adaptation)
//! 2. Implement a named pipe transport as an alternative
//! 3. Use TCP localhost as a last resort
//!
//! The `Transport` enum in `lib.rs` will handle automatic fallback.

use crate::error::{StreamError, StreamResult};
use crate::protocol::EventType;

/// Windows stream producer (NOT YET IMPLEMENTED).
///
/// This is a stub that always returns an error. The actual implementation
/// will use `CreateFileMappingW` and `MapViewOfFile`.
pub struct WindowsStreamProducer {
    _session_id: String,
}

impl WindowsStreamProducer {
    /// Create a new stream producer.
    ///
    /// # Errors
    ///
    /// Always returns `StreamError::Platform` until implemented.
    pub fn new(session_id: &str) -> StreamResult<Self> {
        Err(StreamError::Platform(format!(
            "Windows shared memory not yet implemented for session '{}'. \
             See windows/mod.rs for implementation plan.",
            session_id
        )))
    }

    /// Get the session ID.
    #[allow(dead_code)]
    pub fn session_id(&self) -> &str {
        &self._session_id
    }

    /// Write an event to the stream.
    #[allow(dead_code)]
    pub fn write_event(
        &self,
        _event_type: EventType,
        _sequence: i64,
        _payload: &[u8],
    ) -> StreamResult<u64> {
        Err(StreamError::Platform(
            "Windows shared memory not yet implemented".into(),
        ))
    }

    /// Shutdown the stream.
    #[allow(dead_code)]
    pub fn shutdown(&self) {
        // No-op for stub
    }
}

/// Windows stream consumer (NOT YET IMPLEMENTED).
///
/// This is a stub that always returns an error. The actual implementation
/// will use `OpenFileMappingW` and `MapViewOfFile`.
pub struct WindowsStreamConsumer {
    _session_id: String,
}

impl WindowsStreamConsumer {
    /// Open an existing stream.
    ///
    /// # Errors
    ///
    /// Always returns `StreamError::Platform` until implemented.
    pub fn open(session_id: &str) -> StreamResult<Self> {
        Err(StreamError::Platform(format!(
            "Windows shared memory not yet implemented for session '{}'. \
             See windows/mod.rs for implementation plan.",
            session_id
        )))
    }

    /// Get the session ID.
    #[allow(dead_code)]
    pub fn session_id(&self) -> &str {
        &self._session_id
    }

    /// Check if shutdown has been requested.
    #[allow(dead_code)]
    pub fn is_shutdown(&self) -> bool {
        true
    }

    /// Try to read an event without blocking.
    #[allow(dead_code)]
    pub fn try_read(&mut self) -> Option<super::StreamEvent> {
        None
    }
}

// Note: When implementing, add these Windows-specific dependencies to Cargo.toml:
//
// [target.'cfg(windows)'.dependencies]
// windows = { version = "0.58", features = [
//     "Win32_Foundation",
//     "Win32_System_Memory",
//     "Win32_System_Threading",
//     "Win32_Security",
// ]}
//
// And enable the feature in the crate:
//
// [features]
// windows = []
