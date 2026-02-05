//! Write-side traits for the Armin session engine.
//!
//! Writes are where reality happens.
//!
//! # Design Principles
//!
//! - All writes commit to SQLite first
//! - Derived state is updated after commit
//! - Side-effects are emitted after derived state is updated
//! - If SQLite write fails, nothing else happens

use crate::types::{
    AgentStatus, Message, MessageId, NewMessage, NewOutboxEvent, NewRepository, NewSession,
    NewSessionSecret, OutboxEvent, Repository, RepositoryId, Session, SessionId, SessionUpdate,
};

/// A writer for session data.
///
/// All write operations follow the strict order:
/// 1. Commit fact to SQLite
/// 2. Update derived state
/// 3. Emit side-effect
pub trait SessionWriter {
    // ========================================================================
    // Repository operations
    // ========================================================================

    /// Creates a new repository.
    ///
    /// Returns the created repository.
    fn create_repository(&self, repo: NewRepository) -> Repository;

    /// Deletes a repository.
    ///
    /// Returns true if the repository was deleted.
    fn delete_repository(&self, id: &RepositoryId) -> bool;

    // ========================================================================
    // Session operations (full metadata)
    // ========================================================================

    /// Creates a new session with full metadata.
    ///
    /// This is the primary method for creating sessions with repository association,
    /// title, worktree configuration, etc.
    fn create_session_with_metadata(&self, session: NewSession) -> Session;

    /// Updates a session's metadata.
    ///
    /// Use this to update title, claude_session_id, status, etc.
    fn update_session(&self, id: &SessionId, update: SessionUpdate) -> bool;

    /// Updates the Claude session ID for a session.
    fn update_session_claude_id(&self, id: &SessionId, claude_session_id: &str) -> bool;

    /// Deletes a session.
    ///
    /// Returns true if the session was deleted.
    fn delete_session(&self, id: &SessionId) -> bool;

    // ========================================================================
    // Session state operations
    // ========================================================================

    /// Updates the agent status for a session.
    ///
    /// Creates the session state row if it doesn't exist.
    fn update_agent_status(&self, session: &SessionId, status: AgentStatus);

    // ========================================================================
    // Message operations
    // ========================================================================

    /// Creates a new session (legacy - creates minimal session record).
    ///
    /// Prefer `create_session_with_metadata` for new code.
    fn create_session(&self) -> SessionId;

    /// Appends a message to a session.
    ///
    /// The sequence number is assigned atomically by Armin. Callers must NOT
    /// provide a sequence number - Armin owns all sequencing and ordering.
    ///
    /// Returns the full message with assigned ID and sequence number.
    ///
    /// # Panics
    ///
    /// Panics if the session does not exist or is closed.
    fn append(&self, session: &SessionId, message: NewMessage) -> Message;

    /// Closes a session.
    ///
    /// After closing, no more messages can be appended to the session.
    fn close(&self, session: &SessionId);

    // ========================================================================
    // Session secrets operations
    // ========================================================================

    /// Sets a session secret.
    ///
    /// The secret should be encrypted before calling this method.
    fn set_session_secret(&self, secret: NewSessionSecret);

    /// Deletes a session secret.
    fn delete_session_secret(&self, session: &SessionId) -> bool;

    // ========================================================================
    // Outbox operations
    // ========================================================================

    /// Inserts a new outbox event.
    fn insert_outbox_event(&self, event: NewOutboxEvent) -> OutboxEvent;

    /// Marks outbox events as sent.
    fn mark_outbox_sent(&self, batch_id: &str, event_ids: &[String]);

    /// Marks outbox events as acknowledged.
    fn mark_outbox_acked(&self, batch_id: &str);

    // ========================================================================
    // Supabase message outbox operations
    // ========================================================================

    /// Insert a message into the Supabase message outbox.
    fn insert_supabase_message_outbox(&self, message_id: &MessageId);

    /// Mark messages as sent to Supabase.
    fn mark_supabase_messages_sent(&self, message_ids: &[MessageId]);

    /// Mark messages as failed to sync (updates retry count and last error).
    fn mark_supabase_messages_failed(&self, message_ids: &[MessageId], error: &str);

    /// Delete messages from the Supabase outbox.
    fn delete_supabase_message_outbox(&self, message_ids: &[MessageId]);

    // ========================================================================
    // Supabase sync state operations (cursor-based)
    // ========================================================================

    /// Marks sync as successful for a session up to a sequence number.
    fn mark_supabase_sync_success(&self, session: &SessionId, up_to_sequence: i64);

    /// Marks sync as failed for a session (increments retry count).
    fn mark_supabase_sync_failed(&self, session: &SessionId, error: &str);
}
