//! Unix shared memory producer (daemon side).
//!
//! The producer is responsible for:
//! - Creating and initializing the shared memory region
//! - Writing events to the ring buffer
//! - Signaling consumers when new data is available
//! - Cleaning up on shutdown

use std::ptr;
use std::sync::atomic::Ordering;

use tracing::{debug, error, info, warn};

use crate::error::{StreamError, StreamResult};
use crate::protocol::{
    calculate_shm_size, flags, slot_flags, EventType, SlotHeader, StreamHeader,
    DEFAULT_SLOT_COUNT, DEFAULT_SLOT_SIZE, HEADER_SIZE, SLOT_HEADER_SIZE,
};

use super::{close_shm, create_shm, shm_name, unlink_shm, wake_consumer};

/// Producer for writing events to shared memory.
///
/// # Thread Safety
///
/// `UnixStreamProducer` is `Send` but not `Sync`. Only one thread should
/// write at a time (Single Producer in SPSC).
pub struct UnixStreamProducer {
    /// Pointer to mapped shared memory
    ptr: *mut u8,
    /// File descriptor
    fd: libc::c_int,
    /// Total mapped size
    size: usize,
    /// Shared memory name (for cleanup)
    name: String,
    /// Session ID
    session_id: String,
    /// Slot size configuration
    slot_size: u32,
    /// Slot count configuration (kept for potential future use in diagnostics)
    #[allow(dead_code)]
    slot_count: u32,
}

// SAFETY: The producer owns the shared memory mapping and can be sent between threads.
// The shared memory is coordinated using atomics for thread-safe access.
unsafe impl Send for UnixStreamProducer {}

// SAFETY: The producer uses atomic operations for all shared state coordination.
// While concurrent writes to the same slot would be unsafe, the atomic write_seq
// ensures slots are claimed exclusively. Multiple threads can safely hold references
// to the producer (for Arc<StreamProducer> in HashMap), but actual writes should
// be serialized by the caller for SPSC semantics.
unsafe impl Sync for UnixStreamProducer {}

impl UnixStreamProducer {
    /// Create a new stream producer for a session.
    ///
    /// This creates and initializes the shared memory region. The region will
    /// be cleaned up when the producer is dropped.
    pub fn new(session_id: &str) -> StreamResult<Self> {
        Self::with_config(session_id, DEFAULT_SLOT_SIZE, DEFAULT_SLOT_COUNT)
    }

    /// Create a new stream producer with custom configuration.
    pub fn with_config(session_id: &str, slot_size: u32, slot_count: u32) -> StreamResult<Self> {
        if !slot_count.is_power_of_two() {
            return Err(StreamError::SharedMemory(
                "slot_count must be power of 2".into(),
            ));
        }

        let name = shm_name(session_id);
        let size = calculate_shm_size(slot_size, slot_count);

        info!(
            session_id = %session_id,
            name = %name,
            size = %size,
            slot_size = %slot_size,
            slot_count = %slot_count,
            "Creating stream producer"
        );

        let (ptr, fd) = create_shm(&name, size)?;

        // Initialize header
        let header = unsafe { &mut *(ptr as *mut StreamHeader) };
        header.init(slot_size, slot_count);

        // Zero out the ring buffer
        unsafe {
            ptr::write_bytes(ptr.add(HEADER_SIZE), 0, size - HEADER_SIZE);
        }

        debug!(session_id = %session_id, "Stream producer initialized");

        Ok(Self {
            ptr,
            fd,
            size,
            name,
            session_id: session_id.to_string(),
            slot_size,
            slot_count,
        })
    }

    /// Get the session ID this producer is for.
    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    /// Get the shared memory name.
    pub fn shm_name(&self) -> &str {
        &self.name
    }

    /// Check if a consumer is connected (has read at least one event).
    pub fn has_consumer(&self) -> bool {
        let header = self.header();
        header.read_seq.load(Ordering::Acquire) > 0
    }

    /// Get the number of unread events in the buffer.
    pub fn pending_events(&self) -> u64 {
        self.header().available_read_slots()
    }

    /// Write an event to the stream.
    ///
    /// # Returns
    ///
    /// - `Ok(sequence)` - The sequence number assigned to this event
    /// - `Err(BufferFull)` - Buffer is full, consider waiting or dropping
    /// - `Err(PayloadTooLarge)` - Payload exceeds slot size
    pub fn write_event(
        &self,
        event_type: EventType,
        sequence: i64,
        payload: &[u8],
    ) -> StreamResult<u64> {
        self.write_event_for_session(&self.session_id, event_type, sequence, payload)
    }

    /// Write an event for a specific session (useful for multiplexed streams).
    pub fn write_event_for_session(
        &self,
        session_id: &str,
        event_type: EventType,
        sequence: i64,
        payload: &[u8],
    ) -> StreamResult<u64> {
        let header = self.header();

        // Check shutdown
        if header.is_shutdown() {
            return Err(StreamError::Shutdown);
        }

        let max_payload = SlotHeader::max_payload_size(self.slot_size);
        let truncated = payload.len() > max_payload;
        let actual_len = payload.len().min(max_payload);

        if truncated {
            warn!(
                session_id = %session_id,
                payload_len = %payload.len(),
                max_len = %max_payload,
                "Payload truncated to fit slot"
            );
        }

        // Check if buffer is full
        if header.is_full() {
            // Set overflow flag
            header.flags.fetch_or(flags::OVERFLOW, Ordering::Release);
            return Err(StreamError::BufferFull);
        }

        // Get write position
        let write_seq = header.write_seq.load(Ordering::Acquire);
        let slot_offset = header.slot_offset(write_seq);

        // Validate session_id length
        if session_id.len() != 36 {
            return Err(StreamError::InvalidSessionId);
        }

        // Write slot header
        let slot_header = unsafe { &mut *(self.ptr.add(slot_offset) as *mut SlotHeader) };
        slot_header.len = actual_len as u32;
        slot_header.event_type = event_type as u8;
        slot_header.flags = slot_flags::VALID | if truncated { slot_flags::TRUNCATED } else { 0 };
        slot_header.sequence = sequence;
        slot_header.session_id[..36].copy_from_slice(session_id.as_bytes());

        // Write payload
        if actual_len > 0 {
            unsafe {
                ptr::copy_nonoverlapping(
                    payload.as_ptr(),
                    self.ptr.add(slot_offset + SLOT_HEADER_SIZE),
                    actual_len,
                );
            }
        }

        // Memory barrier and increment write sequence
        header.write_seq.fetch_add(1, Ordering::Release);

        // Wake consumer
        wake_consumer(header);

        debug!(
            session_id = %session_id,
            event_type = ?event_type,
            sequence = %sequence,
            payload_len = %actual_len,
            "Wrote event to stream"
        );

        Ok(write_seq)
    }

    /// Write a raw JSON event (convenience method for Claude events).
    pub fn write_json_event(&self, sequence: i64, json: &str) -> StreamResult<u64> {
        self.write_event(EventType::ClaudeEvent, sequence, json.as_bytes())
    }

    /// Write a terminal output event.
    pub fn write_terminal_output(&self, sequence: i64, output: &str) -> StreamResult<u64> {
        self.write_event(EventType::TerminalOutput, sequence, output.as_bytes())
    }

    /// Write a terminal finished event.
    pub fn write_terminal_finished(&self, sequence: i64, exit_code: i32) -> StreamResult<u64> {
        let payload = exit_code.to_le_bytes();
        self.write_event(EventType::TerminalFinished, sequence, &payload)
    }

    /// Request shutdown - signals consumers to disconnect.
    pub fn shutdown(&self) {
        info!(session_id = %self.session_id, "Shutting down stream producer");
        let header = self.header();
        header.set_shutdown();
        wake_consumer(header);
    }

    /// Get reference to the stream header.
    fn header(&self) -> &StreamHeader {
        unsafe { &*(self.ptr as *const StreamHeader) }
    }
}

impl Drop for UnixStreamProducer {
    fn drop(&mut self) {
        info!(session_id = %self.session_id, "Dropping stream producer");

        // Signal shutdown
        self.shutdown();

        // Unmap and close
        unsafe {
            close_shm(self.ptr, self.size, self.fd);
        }

        // Remove shared memory object
        if let Err(e) = unlink_shm(&self.name) {
            error!(
                session_id = %self.session_id,
                error = %e,
                "Failed to unlink shared memory"
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn test_session_id() -> String {
        Uuid::new_v4().to_string()
    }

    #[test]
    fn test_producer_creation() {
        let session_id = test_session_id();
        let producer = UnixStreamProducer::new(&session_id).unwrap();

        assert_eq!(producer.session_id(), session_id);
        assert!(!producer.has_consumer());
        assert_eq!(producer.pending_events(), 0);
    }

    #[test]
    fn test_write_event() {
        let session_id = test_session_id();
        let producer = UnixStreamProducer::new(&session_id).unwrap();

        let seq = producer
            .write_event(EventType::ClaudeEvent, 1, b"test payload")
            .unwrap();

        assert_eq!(seq, 0);
        assert_eq!(producer.pending_events(), 1);
    }

    #[test]
    fn test_write_multiple_events() {
        let session_id = test_session_id();
        let producer = UnixStreamProducer::new(&session_id).unwrap();

        for i in 0..10 {
            let seq = producer
                .write_event(EventType::ClaudeEvent, i, format!("event {}", i).as_bytes())
                .unwrap();
            assert_eq!(seq, i as u64);
        }

        assert_eq!(producer.pending_events(), 10);
    }

    #[test]
    fn test_shutdown() {
        let session_id = test_session_id();
        let producer = UnixStreamProducer::new(&session_id).unwrap();

        producer.shutdown();

        let result = producer.write_event(EventType::ClaudeEvent, 1, b"test");
        assert!(matches!(result, Err(StreamError::Shutdown)));
    }

    #[test]
    fn test_invalid_session_id() {
        let session_id = test_session_id();
        let producer = UnixStreamProducer::new(&session_id).unwrap();

        let result = producer.write_event_for_session(
            "invalid-session-id", // Not 36 chars
            EventType::ClaudeEvent,
            1,
            b"test",
        );

        assert!(matches!(result, Err(StreamError::InvalidSessionId)));
    }
}
