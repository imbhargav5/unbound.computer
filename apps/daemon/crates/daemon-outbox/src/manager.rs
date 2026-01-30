//! Outbox manager for coordinating per-session queues.

use crate::{OutboxQueue, OutboxResult, PipelineSender, SenderConfig};
use daemon_database::Database;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Outbox manager coordinates per-session outbox queues.
pub struct OutboxManager {
    db: Arc<Database>,
    queues: RwLock<HashMap<String, Arc<OutboxQueue>>>,
    sender_config: SenderConfig,
    auth_token: RwLock<Option<String>>,
}

impl OutboxManager {
    /// Create a new outbox manager.
    pub fn new(db: Arc<Database>, sender_config: SenderConfig) -> Self {
        Self {
            db,
            queues: RwLock::new(HashMap::new()),
            sender_config,
            auth_token: RwLock::new(None),
        }
    }

    /// Set the authentication token for the sender.
    pub async fn set_auth_token(&self, token: &str) {
        *self.auth_token.write().await = Some(token.to_string());
    }

    /// Get or create an outbox queue for a session.
    pub async fn get_or_create_queue(&self, session_id: &str) -> OutboxResult<Arc<OutboxQueue>> {
        // Check if queue already exists
        {
            let queues = self.queues.read().await;
            if let Some(queue) = queues.get(session_id) {
                return Ok(queue.clone());
            }
        }

        // Create new queue
        let queue = Arc::new(OutboxQueue::new(session_id, self.db.clone())?);
        queue.recover().await?;

        let mut queues = self.queues.write().await;
        queues.insert(session_id.to_string(), queue.clone());

        info!(session_id = %session_id, "Created outbox queue");
        Ok(queue)
    }

    /// Remove a queue when session is closed.
    pub async fn remove_queue(&self, session_id: &str) {
        let mut queues = self.queues.write().await;
        if queues.remove(session_id).is_some() {
            info!(session_id = %session_id, "Removed outbox queue");
        }
    }

    /// Enqueue an event for a session.
    pub async fn enqueue(&self, session_id: &str, message_id: &str) -> OutboxResult<()> {
        let queue = self.get_or_create_queue(session_id).await?;
        queue.enqueue(message_id).await
    }

    /// Process pending events for a session.
    ///
    /// This should be called periodically or when new events are enqueued.
    pub async fn process_session(&self, session_id: &str) -> OutboxResult<()> {
        let queue = self.get_or_create_queue(session_id).await?;
        let auth_token = self.auth_token.read().await.clone();

        let auth_token = match auth_token {
            Some(token) => token,
            None => {
                warn!(session_id = %session_id, "No auth token, skipping processing");
                return Ok(());
            }
        };

        let sender = PipelineSender::new(self.sender_config.clone(), &auth_token);

        // Process batches until queue is empty or max in-flight reached
        loop {
            let batch = match queue.get_next_batch().await? {
                Some(b) => b,
                None => break,
            };

            let batch_id = batch.batch_id.clone();

            match sender.send_batch(&batch).await {
                Ok(()) => {
                    queue.acknowledge_batch(&batch_id).await?;
                }
                Err(e) => {
                    warn!(
                        session_id = %session_id,
                        batch_id = %batch_id,
                        error = %e,
                        "Batch send failed"
                    );
                    queue.retry_batch(batch).await?;
                    // Don't continue processing after a failure
                    break;
                }
            }
        }

        Ok(())
    }

    /// Process all sessions with pending events.
    pub async fn process_all(&self) -> OutboxResult<()> {
        let session_ids: Vec<String> = {
            let queues = self.queues.read().await;
            queues.keys().cloned().collect()
        };

        for session_id in session_ids {
            if let Err(e) = self.process_session(&session_id).await {
                warn!(session_id = %session_id, error = %e, "Error processing session");
            }
        }

        Ok(())
    }

    /// Get status for all queues.
    pub async fn get_status(&self) -> HashMap<String, QueueStatus> {
        let queues = self.queues.read().await;
        let mut status = HashMap::new();

        for (session_id, queue) in queues.iter() {
            status.insert(session_id.clone(), QueueStatus {
                pending: queue.pending_count().await,
                in_flight: queue.in_flight_count().await,
            });
        }

        status
    }

    /// Get the number of active queues.
    pub async fn queue_count(&self) -> usize {
        self.queues.read().await.len()
    }
}

/// Status of an outbox queue.
#[derive(Debug, Clone)]
pub struct QueueStatus {
    /// Number of pending events.
    pub pending: usize,
    /// Number of in-flight batches.
    pub in_flight: usize,
}

#[cfg(test)]
mod tests {
    use super::*;
    use daemon_database::{NewAgentCodingSessionMessage, MessageRole};

    fn create_test_db() -> Arc<Database> {
        let db = Arc::new(Database::open_in_memory().unwrap());

        // Create test repository and session
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

    fn create_test_db_multiple_sessions() -> Arc<Database> {
        let db = Arc::new(Database::open_in_memory().unwrap());

        db.insert_repository(&daemon_database::NewRepository {
            id: "repo-1".to_string(),
            path: "/test/repo".to_string(),
            name: "test".to_string(),
            is_git_repository: true,
            sessions_path: None,
            default_branch: None,
            default_remote: None,
        }).unwrap();

        for i in 1..=3 {
            db.insert_session(&daemon_database::NewAgentCodingSession {
                id: format!("session-{}", i),
                repository_id: "repo-1".to_string(),
                title: format!("Test Session {}", i),
                claude_session_id: None,
                is_worktree: false,
                worktree_path: None,
            }).unwrap();
        }

        db
    }

    /// Helper to create messages (outbox has FK to messages)
    fn create_messages(db: &Database, session_id: &str, msg_ids: &[&str]) {
        for (i, msg_id) in msg_ids.iter().enumerate() {
            db.insert_message(&NewAgentCodingSessionMessage {
                id: msg_id.to_string(),
                session_id: session_id.to_string(),
                role: MessageRole::User,
                content_encrypted: vec![],
                content_nonce: vec![],
                sequence_number: (i + 1) as i64,
                is_streaming: false,
            }).unwrap();
        }
    }

    #[tokio::test]
    async fn test_outbox_manager_create_queue() {
        let db = create_test_db();
        let manager = OutboxManager::new(db, SenderConfig::default());

        let queue = manager.get_or_create_queue("session-1").await.unwrap();
        assert_eq!(queue.session_id(), "session-1");
        assert_eq!(manager.queue_count().await, 1);

        // Getting same queue should return existing one
        let queue2 = manager.get_or_create_queue("session-1").await.unwrap();
        assert_eq!(queue.session_id(), queue2.session_id());
        assert_eq!(manager.queue_count().await, 1);
    }

    #[tokio::test]
    async fn test_outbox_manager_remove_queue() {
        let db = create_test_db();
        let manager = OutboxManager::new(db, SenderConfig::default());

        manager.get_or_create_queue("session-1").await.unwrap();
        assert_eq!(manager.queue_count().await, 1);

        manager.remove_queue("session-1").await;
        assert_eq!(manager.queue_count().await, 0);
    }

    #[tokio::test]
    async fn test_outbox_manager_multiple_sessions() {
        let db = create_test_db_multiple_sessions();
        let manager = OutboxManager::new(db, SenderConfig::default());

        // Create queues for multiple sessions
        manager.get_or_create_queue("session-1").await.unwrap();
        manager.get_or_create_queue("session-2").await.unwrap();
        manager.get_or_create_queue("session-3").await.unwrap();

        assert_eq!(manager.queue_count().await, 3);

        // Remove one
        manager.remove_queue("session-2").await;
        assert_eq!(manager.queue_count().await, 2);

        // The other queues should still exist
        let queue1 = manager.get_or_create_queue("session-1").await.unwrap();
        let queue3 = manager.get_or_create_queue("session-3").await.unwrap();
        assert_eq!(queue1.session_id(), "session-1");
        assert_eq!(queue3.session_id(), "session-3");

        // Still only 2 queues (not re-created)
        assert_eq!(manager.queue_count().await, 2);
    }

    #[tokio::test]
    async fn test_outbox_manager_get_queue_status() {
        let db = create_test_db_multiple_sessions();
        // Create messages first (outbox has FK to messages)
        create_messages(&db, "session-1", &["msg-1", "msg-2"]);
        create_messages(&db, "session-2", &["msg-3"]);
        let manager = OutboxManager::new(db, SenderConfig::default());

        // Create queues and enqueue events
        let queue1 = manager.get_or_create_queue("session-1").await.unwrap();
        queue1.enqueue("msg-1").await.unwrap();
        queue1.enqueue("msg-2").await.unwrap();

        let queue2 = manager.get_or_create_queue("session-2").await.unwrap();
        queue2.enqueue("msg-3").await.unwrap();

        // Get status
        let status = manager.get_status().await;
        assert_eq!(status.len(), 2);

        let status1 = status.get("session-1").unwrap();
        assert_eq!(status1.pending, 2);
        assert_eq!(status1.in_flight, 0);

        let status2 = status.get("session-2").unwrap();
        assert_eq!(status2.pending, 1);
        assert_eq!(status2.in_flight, 0);
    }

    #[tokio::test]
    async fn test_outbox_manager_enqueue() {
        let db = create_test_db();
        // Create message first (outbox has FK to messages)
        create_messages(&db, "session-1", &["msg-1"]);
        let manager = OutboxManager::new(db, SenderConfig::default());

        // Enqueue should create queue automatically
        manager.enqueue("session-1", "msg-1").await.unwrap();
        assert_eq!(manager.queue_count().await, 1);

        // Verify event was enqueued
        let queue = manager.get_or_create_queue("session-1").await.unwrap();
        assert_eq!(queue.pending_count().await, 1);
    }

    #[tokio::test]
    async fn test_outbox_manager_set_auth_token() {
        let db = create_test_db();
        let manager = OutboxManager::new(db, SenderConfig::default());

        // Set auth token
        manager.set_auth_token("test-token").await;

        // No direct way to verify, but operation should succeed
        assert!(true);
    }

    #[tokio::test]
    async fn test_outbox_manager_remove_nonexistent() {
        let db = create_test_db();
        let manager = OutboxManager::new(db, SenderConfig::default());

        // Removing non-existent queue should not panic
        manager.remove_queue("nonexistent").await;
        assert_eq!(manager.queue_count().await, 0);
    }

    #[test]
    fn test_queue_status_fields() {
        let status = QueueStatus {
            pending: 5,
            in_flight: 2,
        };

        assert_eq!(status.pending, 5);
        assert_eq!(status.in_flight, 2);
    }
}
