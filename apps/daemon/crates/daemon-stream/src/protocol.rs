//! Binary protocol for shared memory streaming.
//!
//! This module defines the memory layout for the shared memory ring buffer,
//! designed for zero-copy, low-latency IPC between the daemon and clients.
//!
//! # Memory Layout
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                    Shared Memory Region                          │
//! ├─────────────────────────────────────────────────────────────────┤
//! │  StreamHeader (64 bytes, cache-line aligned)                    │
//! │  ├─ magic: u32          (0x554E4253 = "UNBS")                   │
//! │  ├─ version: u32        (protocol version)                      │
//! │  ├─ write_seq: u64      (producer position, atomic)             │
//! │  ├─ read_seq: u64       (consumer position, atomic)             │
//! │  ├─ flags: u32          (CONNECTED, SHUTDOWN, etc.)             │
//! │  ├─ slot_size: u32      (bytes per slot)                        │
//! │  ├─ slot_count: u32     (number of slots, power of 2)           │
//! │  ├─ wake_futex: u32     (for blocking wait on Linux)            │
//! │  └─ padding[20]         (align to 64 bytes)                     │
//! ├─────────────────────────────────────────────────────────────────┤
//! │  Ring Buffer (slot_count × slot_size bytes)                     │
//! │  ┌─────────┬─────────┬─────────┬─────────┬──────────────────┐   │
//! │  │ Slot 0  │ Slot 1  │ Slot 2  │  ...    │ Slot N-1         │   │
//! │  └─────────┴─────────┴─────────┴─────────┴──────────────────┘   │
//! │                                                                  │
//! │  Each Slot Layout:                                               │
//! │  ├─ SlotHeader (56 bytes)                                       │
//! │  │   ├─ len: u32           (payload length)                     │
//! │  │   ├─ event_type: u8     (EventType enum)                     │
//! │  │   ├─ flags: u8          (slot flags)                         │
//! │  │   ├─ reserved: u16                                           │
//! │  │   ├─ sequence: i64      (event sequence number)              │
//! │  │   └─ session_id: [u8; 36] (UUID as ASCII)                    │
//! │  └─ payload: [u8; slot_size - 56]                               │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!
//! # Design Decisions
//!
//! - **Cache-line alignment**: Header is 64 bytes to avoid false sharing
//! - **Power-of-2 slots**: Enables fast modulo via bitmask
//! - **Atomic sequences**: Lock-free SPSC (single producer, single consumer)
//! - **Fixed slot size**: Simplifies addressing, avoids fragmentation
//! - **Session ID in slot**: Allows single buffer for multiple sessions

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

/// Magic number for validating shared memory region: "UNBS" (UNBound Stream)
pub const MAGIC: u32 = 0x554E4253;

/// Current protocol version. Increment when making breaking changes.
pub const VERSION: u32 = 1;

/// Default slot size (4KB - fits most Claude events with room to spare)
pub const DEFAULT_SLOT_SIZE: u32 = 4096;

/// Default slot count (256 slots = 1MB total buffer)
pub const DEFAULT_SLOT_COUNT: u32 = 256;

/// Size of the stream header (cache-line aligned)
pub const HEADER_SIZE: usize = 64;

/// Size of each slot's header
pub const SLOT_HEADER_SIZE: usize = 56;

/// Header flags
pub mod flags {
    /// Producer is connected and active
    pub const CONNECTED: u32 = 1 << 0;
    /// Shutdown requested - consumers should exit
    pub const SHUTDOWN: u32 = 1 << 1;
    /// Buffer overflow occurred (some events dropped)
    pub const OVERFLOW: u32 = 1 << 2;
}

/// Slot flags
pub mod slot_flags {
    /// Slot contains valid data
    pub const VALID: u8 = 1 << 0;
    /// Payload was truncated to fit slot
    pub const TRUNCATED: u8 = 1 << 1;
}

/// Event types that can be streamed.
///
/// These map to the high-frequency events from daemon-ipc that benefit
/// from shared memory streaming. RPC calls continue to use Unix sockets.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventType {
    /// Raw Claude CLI NDJSON event
    ClaudeEvent = 1,
    /// Terminal stdout/stderr output chunk
    TerminalOutput = 2,
    /// Terminal process finished with exit code
    TerminalFinished = 3,
    /// Real-time streaming content chunk (not persisted)
    StreamingChunk = 4,
    /// Keepalive ping
    Ping = 5,
}

impl EventType {
    /// Convert from raw byte value
    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::ClaudeEvent),
            2 => Some(Self::TerminalOutput),
            3 => Some(Self::TerminalFinished),
            4 => Some(Self::StreamingChunk),
            5 => Some(Self::Ping),
            _ => None,
        }
    }
}

/// Stream header at the start of shared memory.
///
/// This struct is `#[repr(C)]` to ensure consistent layout across
/// Rust, Swift, and C# consumers.
#[repr(C, align(64))]
pub struct StreamHeader {
    /// Magic number for validation (MAGIC = 0x554E4253)
    pub magic: u32,
    /// Protocol version
    pub version: u32,
    /// Producer write position (monotonically increasing)
    pub write_seq: AtomicU64,
    /// Consumer read position (monotonically increasing)
    pub read_seq: AtomicU64,
    /// Flags (see `flags` module)
    pub flags: AtomicU32,
    /// Size of each slot in bytes
    pub slot_size: u32,
    /// Number of slots (must be power of 2)
    pub slot_count: u32,
    /// Futex for blocking wait (Linux) / unused on macOS
    pub wake_futex: AtomicU32,
    /// Reserved for future use
    _reserved: [u8; 16],
}

impl StreamHeader {
    /// Initialize a new header with default values
    pub fn init(&mut self, slot_size: u32, slot_count: u32) {
        assert!(slot_count.is_power_of_two(), "slot_count must be power of 2");
        assert!(slot_size >= SLOT_HEADER_SIZE as u32 + 64, "slot_size too small");

        self.magic = MAGIC;
        self.version = VERSION;
        self.write_seq = AtomicU64::new(0);
        self.read_seq = AtomicU64::new(0);
        self.flags = AtomicU32::new(flags::CONNECTED);
        self.slot_size = slot_size;
        self.slot_count = slot_count;
        self.wake_futex = AtomicU32::new(0);
        self._reserved = [0u8; 16];
    }

    /// Validate the header magic and version
    pub fn validate(&self) -> bool {
        self.magic == MAGIC && self.version == VERSION
    }

    /// Check if shutdown has been requested
    pub fn is_shutdown(&self) -> bool {
        self.flags.load(Ordering::Acquire) & flags::SHUTDOWN != 0
    }

    /// Request shutdown
    pub fn set_shutdown(&self) {
        self.flags.fetch_or(flags::SHUTDOWN, Ordering::Release);
    }

    /// Check if buffer has overflowed
    pub fn has_overflow(&self) -> bool {
        self.flags.load(Ordering::Acquire) & flags::OVERFLOW != 0
    }

    /// Calculate total buffer size needed
    pub fn total_size(&self) -> usize {
        HEADER_SIZE + (self.slot_size as usize * self.slot_count as usize)
    }

    /// Get the mask for fast modulo (slot_count - 1)
    pub fn slot_mask(&self) -> u64 {
        (self.slot_count - 1) as u64
    }

    /// Calculate byte offset for a given slot index
    pub fn slot_offset(&self, index: u64) -> usize {
        HEADER_SIZE + ((index & self.slot_mask()) as usize * self.slot_size as usize)
    }

    /// Get available slots for writing (how many can be written before full)
    pub fn available_write_slots(&self) -> u64 {
        let write = self.write_seq.load(Ordering::Acquire);
        let read = self.read_seq.load(Ordering::Acquire);
        self.slot_count as u64 - (write - read)
    }

    /// Get available slots for reading (how many can be read)
    pub fn available_read_slots(&self) -> u64 {
        let write = self.write_seq.load(Ordering::Acquire);
        let read = self.read_seq.load(Ordering::Acquire);
        write - read
    }

    /// Check if buffer is full
    pub fn is_full(&self) -> bool {
        self.available_write_slots() == 0
    }

    /// Check if buffer is empty
    pub fn is_empty(&self) -> bool {
        self.available_read_slots() == 0
    }
}

/// Header for each slot in the ring buffer.
#[repr(C)]
pub struct SlotHeader {
    /// Length of payload data (excluding this header)
    pub len: u32,
    /// Event type (see EventType enum)
    pub event_type: u8,
    /// Slot flags (see slot_flags module)
    pub flags: u8,
    /// Reserved for alignment
    pub _reserved: u16,
    /// Event sequence number (from daemon's event stream)
    pub sequence: i64,
    /// Session ID as ASCII UUID (36 bytes: 8-4-4-4-12 format)
    pub session_id: [u8; 36],
}

impl SlotHeader {
    /// Maximum payload size for a given slot size
    pub const fn max_payload_size(slot_size: u32) -> usize {
        slot_size as usize - SLOT_HEADER_SIZE
    }

    /// Check if this slot was truncated
    pub fn is_truncated(&self) -> bool {
        self.flags & slot_flags::TRUNCATED != 0
    }

    /// Check if this slot contains valid data
    pub fn is_valid(&self) -> bool {
        self.flags & slot_flags::VALID != 0
    }
}

/// Calculate required shared memory size for given parameters
pub fn calculate_shm_size(slot_size: u32, slot_count: u32) -> usize {
    HEADER_SIZE + (slot_size as usize * slot_count as usize)
}

/// Calculate default shared memory size (1MB + header)
pub fn default_shm_size() -> usize {
    calculate_shm_size(DEFAULT_SLOT_SIZE, DEFAULT_SLOT_COUNT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_header_size() {
        assert_eq!(std::mem::size_of::<StreamHeader>(), HEADER_SIZE);
    }

    #[test]
    fn test_slot_header_size() {
        assert_eq!(std::mem::size_of::<SlotHeader>(), SLOT_HEADER_SIZE);
    }

    #[test]
    fn test_header_alignment() {
        assert_eq!(std::mem::align_of::<StreamHeader>(), 64);
    }

    #[test]
    fn test_slot_mask() {
        let mut header = unsafe { std::mem::zeroed::<StreamHeader>() };
        header.slot_count = 256;
        assert_eq!(header.slot_mask(), 255);

        header.slot_count = 1024;
        assert_eq!(header.slot_mask(), 1023);
    }

    #[test]
    fn test_slot_offset() {
        let mut header = unsafe { std::mem::zeroed::<StreamHeader>() };
        header.slot_size = 4096;
        header.slot_count = 256;

        assert_eq!(header.slot_offset(0), HEADER_SIZE);
        assert_eq!(header.slot_offset(1), HEADER_SIZE + 4096);
        assert_eq!(header.slot_offset(256), HEADER_SIZE); // Wraps around
    }

    #[test]
    fn test_default_shm_size() {
        // 64 bytes header + 256 * 4096 = 64 + 1048576 = 1048640 bytes
        assert_eq!(default_shm_size(), HEADER_SIZE + 1024 * 1024);
    }

    #[test]
    fn test_event_type_roundtrip() {
        for i in 1..=5 {
            let event_type = EventType::from_u8(i).unwrap();
            assert_eq!(event_type as u8, i);
        }
        assert!(EventType::from_u8(0).is_none());
        assert!(EventType::from_u8(6).is_none());
    }

    #[test]
    fn test_max_payload_size() {
        assert_eq!(SlotHeader::max_payload_size(4096), 4096 - SLOT_HEADER_SIZE);
        assert_eq!(SlotHeader::max_payload_size(4096), 4040);
    }
}
