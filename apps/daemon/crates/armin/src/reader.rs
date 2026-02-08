//! Read-side traits for the Armin session engine.
//!
//! Reads are pure, derived, and fast.
//!
//! # Design Principles
//!
//! - Reads never hit SQLite directly (except on recovery)
//! - Reads never emit side-effects
//! - All read state is derived from SQLite on startup

use crate::delta::DeltaView;
use crate::live::LiveSubscription;
use crate::snapshot::SnapshotView;
use crate::types::{
    AblySyncState, PendingSupabaseMessage, Repository, RepositoryId, Session, SessionId,
    SessionPendingSync, SessionSecret, SessionState, SupabaseSyncState,
};
use crate::ArminError;

/// A reader for session data.
///
/// Provides access to snapshots, deltas, and live subscriptions.
pub trait SessionReader {
    // ========================================================================
    // Repository operations
    // ========================================================================

    /// Lists all repositories.
    fn list_repositories(&self) -> Result<Vec<Repository>, ArminError>;

    /// Gets a repository by ID.
    fn get_repository(&self, id: &RepositoryId) -> Result<Option<Repository>, ArminError>;

    /// Gets a repository by path.
    fn get_repository_by_path(&self, path: &str) -> Result<Option<Repository>, ArminError>;

    // ========================================================================
    // Session operations (full metadata)
    // ========================================================================

    /// Lists sessions for a repository.
    fn list_sessions(&self, repository_id: &RepositoryId) -> Result<Vec<Session>, ArminError>;

    /// Gets a session by ID.
    fn get_session(&self, id: &SessionId) -> Result<Option<Session>, ArminError>;

    // ========================================================================
    // Session state operations
    // ========================================================================

    /// Gets the session state (agent status, etc.).
    fn get_session_state(&self, session: &SessionId) -> Result<Option<SessionState>, ArminError>;

    // ========================================================================
    // Message snapshot/delta/live operations
    // ========================================================================

    /// Returns a snapshot view of all sessions.
    fn snapshot(&self) -> SnapshotView;

    /// Returns a delta view for a specific session.
    ///
    /// The delta contains messages appended since the last snapshot.
    fn delta(&self, session: &SessionId) -> DeltaView;

    /// Subscribes to live updates for a specific session.
    ///
    /// Returns a subscription that yields new messages as they are appended.
    fn subscribe(&self, session: &SessionId) -> LiveSubscription;

    // ========================================================================
    // Session secrets operations
    // ========================================================================

    /// Gets the session secret (encrypted).
    fn get_session_secret(&self, session: &SessionId) -> Result<Option<SessionSecret>, ArminError>;

    /// Checks if a session has a stored secret.
    fn has_session_secret(&self, session: &SessionId) -> Result<bool, ArminError>;

    // ========================================================================
    // Supabase message outbox operations
    // ========================================================================

    /// Gets pending Supabase message outbox entries (joined with message content).
    fn get_pending_supabase_messages(&self, limit: usize) -> Result<Vec<PendingSupabaseMessage>, ArminError>;

    // ========================================================================
    // Supabase sync state operations (cursor-based)
    // ========================================================================

    /// Gets the Supabase sync state for a session.
    fn get_supabase_sync_state(&self, session: &SessionId) -> Result<Option<SupabaseSyncState>, ArminError>;

    /// Gets sessions with pending messages to sync (cursor-based).
    fn get_sessions_pending_sync(&self, limit_per_session: usize) -> Result<Vec<SessionPendingSync>, ArminError>;

    // ========================================================================
    // Ably sync state operations (cursor-based)
    // ========================================================================

    /// Gets the Ably sync state for a session.
    fn get_ably_sync_state(&self, session: &SessionId) -> Result<Option<AblySyncState>, ArminError>;

    /// Gets sessions with pending messages to sync via Ably (cursor-based).
    fn get_sessions_pending_ably_sync(&self, limit_per_session: usize) -> Result<Vec<SessionPendingSync>, ArminError>;
}
