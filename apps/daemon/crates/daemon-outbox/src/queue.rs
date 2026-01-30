//! Outbox queue for event delivery.

use crate::{OutboxError, OutboxResult};
use daemon_database::{AgentCodingSessionEventOutbox, Database, NewOutboxEvent, OutboxStatus};
use std::collections::VecDeque;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{debug, info, warn};

/// Maximum events per batch.
pub const MAX_BATCH_SIZE: usize = 50;

/// Maximum in-flight batches.
pub const MAX_IN_FLIGHT_BATCHES: usize = 3;

/// A batch of events to be sent.
#[derive(Debug, Clone)]
pub struct EventBatch {
    /// Unique batch ID.
    pub batch_id: String,
    /// Session ID.
    pub session_id: String,
    /// Events in this batch.
    pub events: Vec<AgentCodingSessionEventOutbox>,
}

impl EventBatch {
    /// Get the event IDs in this batch.
    pub fn event_ids(&self) -> Vec<String> {
        self.events.iter().map(|e| e.event_id.clone()).collect()
    }
}

/// Outbox queue for a single session.
pub struct OutboxQueue {
    session_id: String,
    db: Arc<Database>,
    /// In-memory queue for pending events.
    pending: Mutex<VecDeque<AgentCodingSessionEventOutbox>>,
    /// Currently in-flight batches.
    in_flight: Mutex<Vec<EventBatch>>,
    /// Next sequence number.
    next_sequence: Mutex<i64>,
}

impl OutboxQueue {
    /// Create a new outbox queue for a session.
    pub fn new(session_id: &str, db: Arc<Database>) -> OutboxResult<Self> {
        let next_sequence = db.get_next_outbox_sequence(session_id)?;

        Ok(Self {
            session_id: session_id.to_string(),
            db,
            pending: Mutex::new(VecDeque::new()),
            in_flight: Mutex::new(Vec::new()),
            next_sequence: Mutex::new(next_sequence),
        })
    }

    /// Get the session ID.
    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    /// Initialize queue from database (crash recovery).
    ///
    /// Resets any "sent" events back to "pending" status.
    pub async fn recover(&self) -> OutboxResult<()> {
        let reset_count = self.db.reset_sent_events_to_pending(&self.session_id)?;
        if reset_count > 0 {
            info!(session_id = %self.session_id, count = reset_count, "Recovered sent events to pending");
        }

        // Load pending events into memory
        let pending = self.db.get_pending_outbox_events(&self.session_id, 1000)?;
        let mut queue = self.pending.lock().await;
        queue.extend(pending);

        debug!(session_id = %self.session_id, count = queue.len(), "Loaded pending events");
        Ok(())
    }

    /// Enqueue a new event.
    pub async fn enqueue(&self, message_id: &str) -> OutboxResult<()> {
        let mut next_seq = self.next_sequence.lock().await;
        let sequence_number = *next_seq;
        *next_seq += 1;

        let event_id = uuid::Uuid::new_v4().to_string();

        let event = NewOutboxEvent {
            event_id: event_id.clone(),
            session_id: self.session_id.clone(),
            sequence_number,
            message_id: message_id.to_string(),
        };

        // Persist to database
        self.db.insert_outbox_event(&event)?;

        // Add to in-memory queue
        let outbox_event = AgentCodingSessionEventOutbox {
            event_id,
            session_id: self.session_id.clone(),
            sequence_number,
            relay_send_batch_id: None,
            message_id: message_id.to_string(),
            status: OutboxStatus::Pending,
            retry_count: 0,
            last_error: None,
            created_at: chrono::Utc::now(),
            sent_at: None,
            acked_at: None,
        };

        let mut queue = self.pending.lock().await;
        queue.push_back(outbox_event);

        debug!(session_id = %self.session_id, sequence = sequence_number, "Enqueued event");
        Ok(())
    }

    /// Get the next batch of events to send.
    ///
    /// Returns None if no events are pending or max in-flight batches reached.
    pub async fn get_next_batch(&self) -> OutboxResult<Option<EventBatch>> {
        let in_flight = self.in_flight.lock().await;
        if in_flight.len() >= MAX_IN_FLIGHT_BATCHES {
            debug!(session_id = %self.session_id, "Max in-flight batches reached");
            return Ok(None);
        }
        drop(in_flight);

        let mut pending = self.pending.lock().await;
        if pending.is_empty() {
            return Ok(None);
        }

        // Take up to MAX_BATCH_SIZE events
        let batch_size = std::cmp::min(pending.len(), MAX_BATCH_SIZE);
        let events: Vec<_> = pending.drain(..batch_size).collect();

        let batch_id = uuid::Uuid::new_v4().to_string();
        let batch = EventBatch {
            batch_id: batch_id.clone(),
            session_id: self.session_id.clone(),
            events,
        };

        // Mark as sent in database
        let event_ids = batch.event_ids();
        self.db.mark_outbox_events_sent(&event_ids, &batch_id)?;

        // Track in-flight
        let mut in_flight = self.in_flight.lock().await;
        in_flight.push(batch.clone());

        debug!(
            session_id = %self.session_id,
            batch_id = %batch_id,
            count = event_ids.len(),
            "Created batch"
        );

        Ok(Some(batch))
    }

    /// Acknowledge a batch as successfully sent.
    pub async fn acknowledge_batch(&self, batch_id: &str) -> OutboxResult<()> {
        let mut in_flight = self.in_flight.lock().await;
        in_flight.retain(|b| b.batch_id != batch_id);

        let acked_count = self.db.mark_outbox_batch_acked(batch_id)?;

        info!(
            session_id = %self.session_id,
            batch_id = %batch_id,
            count = acked_count,
            "Batch acknowledged"
        );

        Ok(())
    }

    /// Return a batch to the queue for retry (on failure).
    pub async fn retry_batch(&self, batch: EventBatch) -> OutboxResult<()> {
        let mut in_flight = self.in_flight.lock().await;
        in_flight.retain(|b| b.batch_id != batch.batch_id);
        drop(in_flight);

        // Reset events to pending in database
        self.db.reset_sent_events_to_pending(&self.session_id)?;

        // Add events back to front of queue
        let mut pending = self.pending.lock().await;
        for event in batch.events.into_iter().rev() {
            pending.push_front(event);
        }

        warn!(
            session_id = %self.session_id,
            batch_id = %batch.batch_id,
            "Batch returned for retry"
        );

        Ok(())
    }

    /// Get the number of pending events.
    pub async fn pending_count(&self) -> usize {
        self.pending.lock().await.len()
    }

    /// Get the number of in-flight batches.
    pub async fn in_flight_count(&self) -> usize {
        self.in_flight.lock().await.len()
    }

    /// Check if the queue is empty (no pending or in-flight).
    pub async fn is_empty(&self) -> bool {
        self.pending_count().await == 0 && self.in_flight_count().await == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use daemon_database::{NewAgentCodingSessionMessage, MessageRole};

    fn create_test_db() -> Arc<Database> {
        Arc::new(Database::open_in_memory().unwrap())
    }

    fn setup_test_db() -> Arc<Database> {
        let db = create_test_db();

        db.insert_repository(&daemon_database::NewRepository {
            id: "repo-1".to_string(),
            path: "/test/repo".to_string(),
            name: "test".to_string(),
            is_git_repository: true,
            sessions_path: None,
            default_branch: None,
            default_remote: None,
        }).unwrap();

        db.insert_session(&daemon_database::NewAgentCodingSession {
            id: "session-1".to_string(),
            repository_id: "repo-1".to_string(),
            title: "Test".to_string(),
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        }).unwrap();

        db
    }

    /// Helper to create messages (outbox has FK to messages)
    fn create_messages(db: &Database, session_id: &str, count: i64) {
        for i in 1..=count {
            db.insert_message(&NewAgentCodingSessionMessage {
                id: format!("msg-{}", i),
                session_id: session_id.to_string(),
                role: MessageRole::User,
                content_encrypted: vec![],
                content_nonce: vec![],
                sequence_number: i,
                is_streaming: false,
            }).unwrap();
        }
    }

    #[tokio::test]
    async fn test_outbox_queue_new() {
        let db = setup_test_db();

        let queue = OutboxQueue::new("session-1", db).unwrap();
        assert_eq!(queue.session_id(), "session-1");
        assert_eq!(queue.pending_count().await, 0);
        assert_eq!(queue.in_flight_count().await, 0);
        assert!(queue.is_empty().await);
    }

    #[tokio::test]
    async fn test_outbox_queue_enqueue() {
        let db = setup_test_db();
        create_messages(&db, "session-1", 3);
        let queue = OutboxQueue::new("session-1", db).unwrap();

        // Enqueue events
        queue.enqueue("msg-1").await.unwrap();
        assert_eq!(queue.pending_count().await, 1);
        assert!(!queue.is_empty().await);

        queue.enqueue("msg-2").await.unwrap();
        assert_eq!(queue.pending_count().await, 2);

        queue.enqueue("msg-3").await.unwrap();
        assert_eq!(queue.pending_count().await, 3);
    }

    #[tokio::test]
    async fn test_outbox_queue_get_next_batch() {
        let db = setup_test_db();
        create_messages(&db, "session-1", 5);
        let queue = OutboxQueue::new("session-1", db).unwrap();

        // Enqueue events
        for i in 1..=5 {
            queue.enqueue(&format!("msg-{}", i)).await.unwrap();
        }
        assert_eq!(queue.pending_count().await, 5);

        // Get first batch
        let batch = queue.get_next_batch().await.unwrap().unwrap();
        assert_eq!(batch.session_id, "session-1");
        assert_eq!(batch.events.len(), 5);
        assert!(!batch.batch_id.is_empty());

        // Pending should now be empty
        assert_eq!(queue.pending_count().await, 0);

        // In-flight should have one batch
        assert_eq!(queue.in_flight_count().await, 1);

        // Getting another batch when empty returns None
        let next_batch = queue.get_next_batch().await.unwrap();
        assert!(next_batch.is_none());
    }

    #[tokio::test]
    async fn test_outbox_queue_batch_size_limit() {
        let db = setup_test_db();
        create_messages(&db, "session-1", 60);
        let queue = OutboxQueue::new("session-1", db).unwrap();

        // Enqueue more than MAX_BATCH_SIZE events
        for i in 1..=60 {
            queue.enqueue(&format!("msg-{}", i)).await.unwrap();
        }
        assert_eq!(queue.pending_count().await, 60);

        // First batch should be limited to MAX_BATCH_SIZE
        let batch = queue.get_next_batch().await.unwrap().unwrap();
        assert_eq!(batch.events.len(), MAX_BATCH_SIZE);
        assert_eq!(queue.pending_count().await, 10);

        // Second batch gets remaining events
        let batch2 = queue.get_next_batch().await.unwrap().unwrap();
        assert_eq!(batch2.events.len(), 10);
        assert_eq!(queue.pending_count().await, 0);
    }

    #[tokio::test]
    async fn test_outbox_queue_in_flight_limit() {
        let db = setup_test_db();
        create_messages(&db, "session-1", 200);
        let queue = OutboxQueue::new("session-1", db).unwrap();

        // Enqueue enough events for multiple batches
        for i in 1..=200 {
            queue.enqueue(&format!("msg-{}", i)).await.unwrap();
        }

        // Get MAX_IN_FLIGHT_BATCHES batches
        for _ in 0..MAX_IN_FLIGHT_BATCHES {
            let batch = queue.get_next_batch().await.unwrap();
            assert!(batch.is_some());
        }

        assert_eq!(queue.in_flight_count().await, MAX_IN_FLIGHT_BATCHES);

        // Next batch should be None because max in-flight reached
        let batch = queue.get_next_batch().await.unwrap();
        assert!(batch.is_none());
    }

    #[tokio::test]
    async fn test_outbox_queue_acknowledge_batch() {
        let db = setup_test_db();
        create_messages(&db, "session-1", 1);
        let queue = OutboxQueue::new("session-1", db).unwrap();

        // Enqueue and get batch
        queue.enqueue("msg-1").await.unwrap();
        let batch = queue.get_next_batch().await.unwrap().unwrap();
        let batch_id = batch.batch_id.clone();

        assert_eq!(queue.in_flight_count().await, 1);

        // Acknowledge batch
        queue.acknowledge_batch(&batch_id).await.unwrap();

        // In-flight should be empty
        assert_eq!(queue.in_flight_count().await, 0);
        assert!(queue.is_empty().await);
    }

    #[tokio::test]
    async fn test_outbox_queue_retry_batch() {
        let db = setup_test_db();
        create_messages(&db, "session-1", 2);
        let queue = OutboxQueue::new("session-1", db).unwrap();

        // Enqueue events
        queue.enqueue("msg-1").await.unwrap();
        queue.enqueue("msg-2").await.unwrap();

        // Get batch
        let batch = queue.get_next_batch().await.unwrap().unwrap();
        assert_eq!(queue.pending_count().await, 0);
        assert_eq!(queue.in_flight_count().await, 1);

        // Retry batch (simulating failure)
        queue.retry_batch(batch).await.unwrap();

        // Events should be back in pending queue
        assert_eq!(queue.pending_count().await, 2);
        assert_eq!(queue.in_flight_count().await, 0);
    }

    #[tokio::test]
    async fn test_outbox_queue_recovery() {
        let db = setup_test_db();
        create_messages(&db, "session-1", 3);

        // Insert events directly into database as "sent" (simulating crash)
        for i in 1..=3 {
            db.insert_outbox_event(&daemon_database::NewOutboxEvent {
                event_id: format!("event-{}", i),
                session_id: "session-1".to_string(),
                sequence_number: i,
                message_id: format!("msg-{}", i),
            }).unwrap();
        }
        db.mark_outbox_events_sent(
            &["event-1".to_string(), "event-2".to_string(), "event-3".to_string()],
            "batch-1"
        ).unwrap();

        // Create queue and recover
        let queue = OutboxQueue::new("session-1", db).unwrap();
        queue.recover().await.unwrap();

        // Events should be recovered to pending
        assert_eq!(queue.pending_count().await, 3);
    }

    #[test]
    fn test_event_batch_event_ids() {
        let batch = EventBatch {
            batch_id: "batch-1".to_string(),
            session_id: "session-1".to_string(),
            events: vec![
                AgentCodingSessionEventOutbox {
                    event_id: "event-1".to_string(),
                    session_id: "session-1".to_string(),
                    sequence_number: 1,
                    relay_send_batch_id: None,
                    message_id: "msg-1".to_string(),
                    status: OutboxStatus::Pending,
                    retry_count: 0,
                    last_error: None,
                    created_at: chrono::Utc::now(),
                    sent_at: None,
                    acked_at: None,
                },
                AgentCodingSessionEventOutbox {
                    event_id: "event-2".to_string(),
                    session_id: "session-1".to_string(),
                    sequence_number: 2,
                    relay_send_batch_id: None,
                    message_id: "msg-2".to_string(),
                    status: OutboxStatus::Pending,
                    retry_count: 0,
                    last_error: None,
                    created_at: chrono::Utc::now(),
                    sent_at: None,
                    acked_at: None,
                },
            ],
        };

        let ids = batch.event_ids();
        assert_eq!(ids, vec!["event-1", "event-2"]);
    }

    #[test]
    fn test_max_constants() {
        // Verify constants are reasonable
        assert!(MAX_BATCH_SIZE > 0);
        assert!(MAX_BATCH_SIZE <= 100);
        assert!(MAX_IN_FLIGHT_BATCHES > 0);
        assert!(MAX_IN_FLIGHT_BATCHES <= 10);
    }
}
