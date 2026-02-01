//! Shared memory message cache for ultra-low-latency message access.
//!
//! This module provides a pre-computed, memory-mapped cache of decrypted messages
//! that clients can read directly without IPC overhead.
//!
//! # Performance
//!
//! | Operation | IPC Socket | Message Cache |
//! |-----------|------------|---------------|
//! | Read all messages | ~50-100ms | ~5-10μs |
//! | Read single message | ~1-5ms | ~1μs |
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────┐
//! │                    Shared Memory Region                      │
//! ├─────────────────────────────────────────────────────────────┤
//! │  CacheHeader (64 bytes)                                     │
//! │  ├─ magic: u32          (0x554D5347 = "UMSG")              │
//! │  ├─ version: u32                                            │
//! │  ├─ message_count: u32                                      │
//! │  ├─ total_data_size: u32                                    │
//! │  ├─ last_sequence: i64                                      │
//! │  ├─ update_counter: u64 (atomic, for change detection)     │
//! │  └─ padding                                                 │
//! ├─────────────────────────────────────────────────────────────┤
//! │  MessageIndex[MAX_MESSAGES] (fixed array)                   │
//! │  Each entry: 32 bytes                                       │
//! │  ├─ offset: u32 (into data section)                        │
//! │  ├─ length: u32                                             │
//! │  ├─ sequence: i64                                           │
//! │  ├─ timestamp: i64                                          │
//! │  ├─ role: u8 (user=1, assistant=2, system=3)               │
//! │  └─ padding                                                 │
//! ├─────────────────────────────────────────────────────────────┤
//! │  Data Section (variable length message content)             │
//! │  [msg0_content][msg1_content][msg2_content]...             │
//! └─────────────────────────────────────────────────────────────┘
//! ```
//!
//! # Usage
//!
//! ## Producer (Daemon)
//!
//! ```ignore
//! let cache = MessageCacheProducer::new(&session_id, MAX_CACHE_SIZE)?;
//!
//! // When messages change
//! cache.update(|writer| {
//!     writer.clear();
//!     for msg in messages {
//!         writer.append(msg.sequence, msg.role, msg.timestamp, &msg.content)?;
//!     }
//!     Ok(())
//! })?;
//! ```
//!
//! ## Consumer (Swift/Client)
//!
//! ```ignore
//! let cache = MessageCacheConsumer::open(&session_id)?;
//!
//! // Check if cache changed since last read
//! if cache.update_counter() != last_seen {
//!     let messages = cache.read_all();  // ~5μs
//!     last_seen = cache.update_counter();
//! }
//! ```

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

/// Magic number: "UMSG" (Unbound MeSsaGes)
pub const CACHE_MAGIC: u32 = 0x554D5347;

/// Current cache version
pub const CACHE_VERSION: u32 = 1;

/// Maximum messages in cache (keeps index array fixed-size)
pub const MAX_CACHED_MESSAGES: usize = 1000;

/// Cache header size (cache-line aligned)
pub const CACHE_HEADER_SIZE: usize = 64;

/// Size of each message index entry
pub const MESSAGE_INDEX_SIZE: usize = 32;

/// Index section size
pub const INDEX_SECTION_SIZE: usize = MAX_CACHED_MESSAGES * MESSAGE_INDEX_SIZE;

/// Default data section size (4MB - enough for ~1000 messages averaging 4KB)
pub const DEFAULT_DATA_SIZE: usize = 4 * 1024 * 1024;

/// Total default cache size
pub const DEFAULT_CACHE_SIZE: usize = CACHE_HEADER_SIZE + INDEX_SECTION_SIZE + DEFAULT_DATA_SIZE;

/// Cache header at the start of shared memory.
#[repr(C, align(64))]
pub struct CacheHeader {
    /// Magic number for validation
    pub magic: u32,
    /// Cache version
    pub version: u32,
    /// Number of messages currently in cache
    pub message_count: AtomicU32,
    /// Total bytes used in data section
    pub total_data_size: AtomicU32,
    /// Highest sequence number in cache
    pub last_sequence: i64,
    /// Monotonically increasing counter (atomic) - consumers watch this for changes
    pub update_counter: AtomicU64,
    /// Flags (e.g., UPDATING, VALID)
    pub flags: AtomicU32,
    /// Reserved
    _reserved: [u8; 24],
}

/// Message index entry (fixed size for array indexing).
#[repr(C)]
pub struct MessageIndex {
    /// Offset into data section
    pub offset: u32,
    /// Length of message content
    pub length: u32,
    /// Message sequence number
    pub sequence: i64,
    /// Timestamp (Unix epoch seconds)
    pub timestamp: i64,
    /// Role: 1=user, 2=assistant, 3=system
    pub role: u8,
    /// Reserved/padding
    _reserved: [u8; 7],
}

/// Message role enum matching the index values.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageRole {
    User = 1,
    Assistant = 2,
    System = 3,
}

impl MessageRole {
    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::User),
            2 => Some(Self::Assistant),
            3 => Some(Self::System),
            _ => None,
        }
    }
}

/// Generate the shared memory name for a session's message cache.
pub fn cache_shm_name(session_id: &str) -> String {
    // Format: "/uc_" + first 8 chars of session_id = 12 chars
    let short_id = if session_id.len() > 8 {
        &session_id[..8]
    } else {
        session_id
    };
    format!("/uc_{}", short_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_header_size() {
        assert_eq!(std::mem::size_of::<CacheHeader>(), CACHE_HEADER_SIZE);
    }

    #[test]
    fn test_index_size() {
        assert_eq!(std::mem::size_of::<MessageIndex>(), MESSAGE_INDEX_SIZE);
    }

    #[test]
    fn test_cache_name() {
        let name = cache_shm_name("12345678-1234-1234-1234-123456789012");
        assert_eq!(name, "/uc_12345678");
    }
}
