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
    AgentStatus, CodingSessionStatus, Message, MessageId, NewMessage, NewRepository, NewSession,
    NewSessionSecret, Repository, RepositoryId, Session, SessionId, SessionUpdate,
};
use crate::ArminError;

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
    fn create_repository(&self, repo: NewRepository) -> Result<Repository, ArminError>;

    /// Deletes a repository.
    ///
    /// Returns true if the repository was deleted.
    fn delete_repository(&self, id: &RepositoryId) -> Result<bool, ArminError>;

    /// Updates repository settings.
    ///
    /// This updates the repository defaults persisted in SQLite.
    fn update_repository_settings(
        &self,
        id: &RepositoryId,
        sessions_path: Option<String>,
        default_branch: Option<String>,
        default_remote: Option<String>,
    ) -> Result<bool, ArminError>;

    // ========================================================================
    // Session operations (full metadata)
    // ========================================================================

    /// Creates a new session with full metadata.
    ///
    /// This is the primary method for creating sessions with repository association,
    /// title, worktree configuration, etc.
    fn create_session_with_metadata(&self, session: NewSession) -> Result<Session, ArminError>;

    /// Updates a session's metadata.
    ///
    /// Use this to update title, claude_session_id, status, etc.
    fn update_session(&self, id: &SessionId, update: SessionUpdate) -> Result<bool, ArminError>;

    /// Updates the Claude session ID for a session.
    fn update_session_claude_id(
        &self,
        id: &SessionId,
        claude_session_id: &str,
    ) -> Result<bool, ArminError>;

    /// Deletes a session.
    ///
    /// Returns true if the session was deleted.
    fn delete_session(&self, id: &SessionId) -> Result<bool, ArminError>;

    // ========================================================================
    // Session state operations
    // ========================================================================

    /// Updates the canonical runtime status envelope for a session.
    ///
    /// `device_id` is required and persisted into the runtime envelope.
    fn update_runtime_status(
        &self,
        session: &SessionId,
        device_id: &str,
        status: CodingSessionStatus,
        error_message: Option<String>,
    ) -> Result<(), ArminError>;

    /// Legacy scalar status update helper kept during migration.
    ///
    /// Prefer `update_runtime_status`.
    fn update_agent_status(
        &self,
        session: &SessionId,
        status: AgentStatus,
    ) -> Result<(), ArminError> {
        self.update_runtime_status(
            session,
            "00000000-0000-0000-0000-000000000000",
            status,
            None,
        )
    }

    // ========================================================================
    // Message operations
    // ========================================================================

    /// Creates a new session (legacy - creates minimal session record).
    ///
    /// Prefer `create_session_with_metadata` for new code.
    fn create_session(&self) -> Result<SessionId, ArminError>;

    /// Appends a message to a session.
    ///
    /// The sequence number is assigned atomically by Armin. Callers must NOT
    /// provide a sequence number - Armin owns all sequencing and ordering.
    ///
    /// Returns the full message with assigned ID and sequence number.
    ///
    /// # Errors
    ///
    /// Returns an error if the session does not exist, is closed, or if
    /// the SQLite write fails.
    fn append(&self, session: &SessionId, message: NewMessage) -> Result<Message, ArminError>;

    /// Closes a session.
    ///
    /// After closing, no more messages can be appended to the session.
    fn close(&self, session: &SessionId) -> Result<(), ArminError>;

    // ========================================================================
    // Session secrets operations
    // ========================================================================

    /// Sets a session secret.
    ///
    /// The secret should be encrypted before calling this method.
    fn set_session_secret(&self, secret: NewSessionSecret) -> Result<(), ArminError>;

    /// Deletes a session secret.
    fn delete_session_secret(&self, session: &SessionId) -> Result<bool, ArminError>;

    // ========================================================================
    // Supabase message outbox operations
    // ========================================================================

    /// Insert a message into the Supabase message outbox.
    fn insert_supabase_message_outbox(&self, message_id: &MessageId) -> Result<(), ArminError>;

    /// Mark messages as sent to Supabase.
    fn mark_supabase_messages_sent(&self, message_ids: &[MessageId]) -> Result<(), ArminError>;

    /// Mark messages as failed to sync (updates retry count and last error).
    fn mark_supabase_messages_failed(
        &self,
        message_ids: &[MessageId],
        error: &str,
    ) -> Result<(), ArminError>;

    /// Delete messages from the Supabase outbox.
    fn delete_supabase_message_outbox(&self, message_ids: &[MessageId]) -> Result<(), ArminError>;

    // ========================================================================
    // Supabase sync state operations (cursor-based)
    // ========================================================================

    /// Marks sync as successful for a session up to a sequence number.
    fn mark_supabase_sync_success(
        &self,
        session: &SessionId,
        up_to_sequence: i64,
    ) -> Result<(), ArminError>;

    /// Marks sync as failed for a session (increments retry count).
    fn mark_supabase_sync_failed(&self, session: &SessionId, error: &str)
        -> Result<(), ArminError>;

    // ========================================================================
    // Ably sync state operations (cursor-based)
    // ========================================================================

    /// Marks Ably sync as successful for a session up to a sequence number.
    fn mark_ably_sync_success(
        &self,
        session: &SessionId,
        up_to_sequence: i64,
    ) -> Result<(), ArminError>;

    /// Marks Ably sync as failed for a session (increments retry count).
    fn mark_ably_sync_failed(&self, session: &SessionId, error: &str) -> Result<(), ArminError>;
}
