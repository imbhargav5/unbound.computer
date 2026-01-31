//! Unix shared memory consumer (client side).
//!
//! The consumer is responsible for:
//! - Opening and mapping the existing shared memory region
//! - Reading events from the ring buffer
//! - Waiting for new events efficiently
//! - Handling producer shutdown gracefully

use std::sync::atomic::Ordering;
use std::time::{Duration, Instant};

use tracing::{debug, trace};

use crate::error::{StreamError, StreamResult};
use crate::protocol::{slot_flags, EventType, SlotHeader, StreamHeader, SLOT_HEADER_SIZE};

use super::{close_shm, open_shm, shm_name, wait_for_data};

/// A single event read from the stream.
#[derive(Debug, Clone)]
pub struct StreamEvent {
    /// Session ID this event belongs to
    pub session_id: String,
    /// Event type
    pub event_type: EventType,
    /// Event sequence number
    pub sequence: i64,
    /// Event payload (raw bytes)
    pub payload: Vec<u8>,
    /// Whether the payload was truncated
    pub truncated: bool,
}

impl StreamEvent {
    /// Get payload as string (for text-based events like JSON)
    pub fn payload_str(&self) -> Result<&str, std::str::Utf8Error> {
        std::str::from_utf8(&self.payload)
    }

    /// Get payload as string, lossy conversion
    pub fn payload_string_lossy(&self) -> String {
        String::from_utf8_lossy(&self.payload).into_owned()
    }
}

/// Consumer for reading events from shared memory.
///
/// # Thread Safety
///
/// `UnixStreamConsumer` is `Send` but not `Sync`. Only one thread should
/// read at a time (Single Consumer in SPSC).
pub struct UnixStreamConsumer {
    /// Pointer to mapped shared memory
    ptr: *mut u8,
    /// File descriptor
    fd: libc::c_int,
    /// Total mapped size
    size: usize,
    /// Session ID
    session_id: String,
    /// Local read position (tracks what we've read)
    read_seq: u64,
    /// Last seen futex value (for efficient waiting)
    last_futex: u32,
}

// SAFETY: The consumer owns its view of the shared memory and can be sent between threads.
// However, concurrent reads are not safe (SPSC design).
unsafe impl Send for UnixStreamConsumer {}

impl UnixStreamConsumer {
    /// Open an existing stream for a session.
    ///
    /// The stream must have been created by a producer. This will fail if
    /// the shared memory doesn't exist or has an invalid header.
    pub fn open(session_id: &str) -> StreamResult<Self> {
        let name = shm_name(session_id);

        debug!(session_id = %session_id, name = %name, "Opening stream consumer");

        let (ptr, fd, size) = open_shm(&name)?;

        // Validate header again after full mapping
        let header = unsafe { &*(ptr as *const StreamHeader) };
        if !header.validate() {
            unsafe {
                close_shm(ptr, size, fd);
            }
            return Err(StreamError::InvalidHeader(
                "header validation failed after mapping".into(),
            ));
        }

        debug!(
            session_id = %session_id,
            slot_size = %header.slot_size,
            slot_count = %header.slot_count,
            "Stream consumer opened"
        );

        Ok(Self {
            ptr,
            fd,
            size,
            session_id: session_id.to_string(),
            read_seq: 0,
            last_futex: 0,
        })
    }

    /// Get the session ID this consumer is for.
    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    /// Check if the stream has been shut down by the producer.
    pub fn is_shutdown(&self) -> bool {
        self.header().is_shutdown()
    }

    /// Check if there are events available to read.
    pub fn has_events(&self) -> bool {
        let header = self.header();
        let write_seq = header.write_seq.load(Ordering::Acquire);
        self.read_seq < write_seq
    }

    /// Get the number of events available to read.
    pub fn available_events(&self) -> u64 {
        let header = self.header();
        let write_seq = header.write_seq.load(Ordering::Acquire);
        write_seq.saturating_sub(self.read_seq)
    }

    /// Try to read the next event without blocking.
    ///
    /// Returns `None` if no events are available or stream is shut down.
    pub fn try_read(&mut self) -> Option<StreamEvent> {
        // Get header pointer for atomic reads
        let header_ptr = self.ptr as *const StreamHeader;
        let header = unsafe { &*header_ptr };

        // Check shutdown
        if header.is_shutdown() && !self.has_events() {
            return None;
        }

        // Check if data available
        let write_seq = header.write_seq.load(Ordering::Acquire);
        if self.read_seq >= write_seq {
            return None;
        }

        // Read the event
        let event = self.read_slot(self.read_seq);

        // Update read position
        self.read_seq += 1;

        // Update shared read_seq periodically (every 8 events)
        // This reduces contention while still allowing producer to track progress
        if self.read_seq % 8 == 0 {
            header.read_seq.store(self.read_seq, Ordering::Release);
        }

        Some(event)
    }

    /// Read the next event, blocking until available.
    ///
    /// # Returns
    ///
    /// - `Ok(Some(event))` - An event was read
    /// - `Ok(None)` - Stream was shut down
    /// - `Err(_)` - An error occurred
    pub fn read(&mut self) -> StreamResult<Option<StreamEvent>> {
        self.read_timeout(None)
    }

    /// Read the next event with a timeout.
    ///
    /// # Returns
    ///
    /// - `Ok(Some(event))` - An event was read
    /// - `Ok(None)` - Timeout elapsed or stream was shut down
    /// - `Err(_)` - An error occurred
    pub fn read_timeout(&mut self, timeout: Option<Duration>) -> StreamResult<Option<StreamEvent>> {
        let deadline = timeout.map(|t| Instant::now() + t);

        loop {
            // Try non-blocking read first
            if let Some(event) = self.try_read() {
                return Ok(Some(event));
            }

            // Check shutdown
            if self.is_shutdown() {
                return Ok(None);
            }

            // Check timeout
            if let Some(deadline) = deadline {
                if Instant::now() >= deadline {
                    return Ok(None);
                }
            }

            // Wait for data
            let header = self.header();
            let current_futex = header.wake_futex.load(Ordering::Acquire);

            // Only wait if futex hasn't changed (avoid missed wakeups)
            if current_futex == self.last_futex {
                let wait_ms = deadline.map(|d| {
                    d.saturating_duration_since(Instant::now())
                        .as_millis()
                        .min(100) as u32 // Cap at 100ms for responsiveness
                });
                wait_for_data(header, current_futex, wait_ms);
            }

            self.last_futex = header.wake_futex.load(Ordering::Acquire);
        }
    }

    /// Read all available events into a vector.
    ///
    /// This is useful for batch processing. Returns an empty vector if
    /// no events are available.
    pub fn read_all(&mut self) -> Vec<StreamEvent> {
        let mut events = Vec::new();
        while let Some(event) = self.try_read() {
            events.push(event);
        }
        events
    }

    /// Read up to `max` events into a vector.
    pub fn read_batch(&mut self, max: usize) -> Vec<StreamEvent> {
        let mut events = Vec::with_capacity(max.min(64));
        for _ in 0..max {
            match self.try_read() {
                Some(event) => events.push(event),
                None => break,
            }
        }
        events
    }

    /// Skip events to catch up to the current write position.
    ///
    /// Use this when you want to only receive new events and don't care
    /// about events that were written before you connected.
    pub fn skip_to_latest(&mut self) -> u64 {
        // Get header pointer to avoid borrow conflict
        let header_ptr = self.ptr as *const StreamHeader;
        let header = unsafe { &*header_ptr };

        let write_seq = header.write_seq.load(Ordering::Acquire);
        let skipped = write_seq.saturating_sub(self.read_seq);
        self.read_seq = write_seq;
        header.read_seq.store(self.read_seq, Ordering::Release);

        if skipped > 0 {
            debug!(
                session_id = %self.session_id,
                skipped = %skipped,
                "Skipped to latest position"
            );
        }

        skipped
    }

    /// Get reference to the stream header.
    fn header(&self) -> &StreamHeader {
        unsafe { &*(self.ptr as *const StreamHeader) }
    }

    /// Read a slot at the given sequence number.
    fn read_slot(&self, seq: u64) -> StreamEvent {
        let header = self.header();
        let slot_offset = header.slot_offset(seq);

        let slot_header = unsafe { &*(self.ptr.add(slot_offset) as *const SlotHeader) };

        // Read session ID
        let session_id = String::from_utf8_lossy(&slot_header.session_id).into_owned();

        // Read event type
        let event_type = EventType::from_u8(slot_header.event_type)
            .unwrap_or(EventType::ClaudeEvent);

        // Check flags
        let truncated = slot_header.flags & slot_flags::TRUNCATED != 0;

        // Read payload
        let payload_len = slot_header.len as usize;
        let payload = if payload_len > 0 {
            let mut buf = vec![0u8; payload_len];
            unsafe {
                std::ptr::copy_nonoverlapping(
                    self.ptr.add(slot_offset + SLOT_HEADER_SIZE),
                    buf.as_mut_ptr(),
                    payload_len,
                );
            }
            buf
        } else {
            Vec::new()
        };

        trace!(
            session_id = %session_id,
            event_type = ?event_type,
            sequence = %slot_header.sequence,
            payload_len = %payload_len,
            "Read event from stream"
        );

        StreamEvent {
            session_id,
            event_type,
            sequence: slot_header.sequence,
            payload,
            truncated,
        }
    }
}

impl Drop for UnixStreamConsumer {
    fn drop(&mut self) {
        debug!(session_id = %self.session_id, "Dropping stream consumer");

        // Update final read position
        let header = self.header();
        header.read_seq.store(self.read_seq, Ordering::Release);

        // Unmap and close
        unsafe {
            close_shm(self.ptr, self.size, self.fd);
        }
    }
}

impl Iterator for UnixStreamConsumer {
    type Item = StreamEvent;

    fn next(&mut self) -> Option<Self::Item> {
        // Non-blocking iteration
        self.try_read()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::unix::UnixStreamProducer;
    use uuid::Uuid;

    fn test_session_id() -> String {
        Uuid::new_v4().to_string()
    }

    #[test]
    fn test_consumer_open() {
        let session_id = test_session_id();

        // Create producer first
        let _producer = UnixStreamProducer::new(&session_id).unwrap();

        // Now consumer can open
        let consumer = UnixStreamConsumer::open(&session_id).unwrap();
        assert_eq!(consumer.session_id(), session_id);
        assert!(!consumer.is_shutdown());
        assert!(!consumer.has_events());
    }

    #[test]
    fn test_consumer_open_nonexistent() {
        let session_id = test_session_id();
        let result = UnixStreamConsumer::open(&session_id);
        assert!(result.is_err());
    }

    #[test]
    fn test_producer_consumer_roundtrip() {
        let session_id = test_session_id();

        let producer = UnixStreamProducer::new(&session_id).unwrap();
        let mut consumer = UnixStreamConsumer::open(&session_id).unwrap();

        // Write event
        producer
            .write_event(EventType::ClaudeEvent, 42, b"hello world")
            .unwrap();

        // Read event
        let event = consumer.try_read().unwrap();
        assert_eq!(event.session_id, session_id);
        assert_eq!(event.event_type, EventType::ClaudeEvent);
        assert_eq!(event.sequence, 42);
        assert_eq!(event.payload, b"hello world");
        assert!(!event.truncated);
    }

    #[test]
    fn test_multiple_events() {
        let session_id = test_session_id();

        let producer = UnixStreamProducer::new(&session_id).unwrap();
        let mut consumer = UnixStreamConsumer::open(&session_id).unwrap();

        // Write multiple events
        for i in 0..100 {
            producer
                .write_event(EventType::ClaudeEvent, i, format!("event {}", i).as_bytes())
                .unwrap();
        }

        // Read all
        let events = consumer.read_all();
        assert_eq!(events.len(), 100);

        for (i, event) in events.iter().enumerate() {
            assert_eq!(event.sequence, i as i64);
            assert_eq!(event.payload_str().unwrap(), format!("event {}", i));
        }
    }

    #[test]
    fn test_shutdown_detection() {
        let session_id = test_session_id();

        let producer = UnixStreamProducer::new(&session_id).unwrap();
        let consumer = UnixStreamConsumer::open(&session_id).unwrap();

        assert!(!consumer.is_shutdown());

        producer.shutdown();

        assert!(consumer.is_shutdown());
    }

    #[test]
    fn test_skip_to_latest() {
        let session_id = test_session_id();

        let producer = UnixStreamProducer::new(&session_id).unwrap();
        let mut consumer = UnixStreamConsumer::open(&session_id).unwrap();

        // Write some events
        for i in 0..50 {
            producer
                .write_event(EventType::ClaudeEvent, i, b"old")
                .unwrap();
        }

        // Skip to latest
        let skipped = consumer.skip_to_latest();
        assert_eq!(skipped, 50);

        // Write new event
        producer
            .write_event(EventType::ClaudeEvent, 100, b"new")
            .unwrap();

        // Should only get the new event
        let event = consumer.try_read().unwrap();
        assert_eq!(event.sequence, 100);
        assert_eq!(event.payload, b"new");
    }

    #[test]
    fn test_read_batch() {
        let session_id = test_session_id();

        let producer = UnixStreamProducer::new(&session_id).unwrap();
        let mut consumer = UnixStreamConsumer::open(&session_id).unwrap();

        // Write 100 events
        for i in 0..100 {
            producer
                .write_event(EventType::ClaudeEvent, i, b"data")
                .unwrap();
        }

        // Read in batches
        let batch1 = consumer.read_batch(30);
        assert_eq!(batch1.len(), 30);

        let batch2 = consumer.read_batch(30);
        assert_eq!(batch2.len(), 30);

        let batch3 = consumer.read_batch(100); // Only 40 left
        assert_eq!(batch3.len(), 40);
    }

    #[test]
    fn test_iterator() {
        let session_id = test_session_id();

        let producer = UnixStreamProducer::new(&session_id).unwrap();
        let mut consumer = UnixStreamConsumer::open(&session_id).unwrap();

        for i in 0..10 {
            producer
                .write_event(EventType::ClaudeEvent, i, b"data")
                .unwrap();
        }

        let count = consumer.by_ref().count();
        assert_eq!(count, 10);
    }
}
