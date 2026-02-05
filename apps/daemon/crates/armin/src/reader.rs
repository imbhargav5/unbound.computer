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
    OutboxEvent, PendingSupabaseMessage, Repository, RepositoryId, Session, SessionId,
    SessionPendingSync, SessionSecret, SessionState, SupabaseSyncState,
};

/// A reader for session data.
///
/// Provides access to snapshots, deltas, and live subscriptions.
pub trait SessionReader {
    // ========================================================================
    // Repository operations
    // ========================================================================

    /// Lists all repositories.
    fn list_repositories(&self) -> Vec<Repository>;

    /// Gets a repository by ID.
    fn get_repository(&self, id: &RepositoryId) -> Option<Repository>;

    /// Gets a repository by path.
    fn get_repository_by_path(&self, path: &str) -> Option<Repository>;

    // ========================================================================
    // Session operations (full metadata)
    // ========================================================================

    /// Lists sessions for a repository.
    fn list_sessions(&self, repository_id: &RepositoryId) -> Vec<Session>;

    /// Gets a session by ID.
    fn get_session(&self, id: &SessionId) -> Option<Session>;

    // ========================================================================
    // Session state operations
    // ========================================================================

    /// Gets the session state (agent status, etc.).
    fn get_session_state(&self, session: &SessionId) -> Option<SessionState>;

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
    fn get_session_secret(&self, session: &SessionId) -> Option<SessionSecret>;

    /// Checks if a session has a stored secret.
    fn has_session_secret(&self, session: &SessionId) -> bool;

    // ========================================================================
    // Outbox operations
    // ========================================================================

    /// Gets pending outbox events for a session.
    fn get_pending_outbox_events(&self, session: &SessionId, limit: usize) -> Vec<OutboxEvent>;

    /// Gets pending Supabase message outbox entries (joined with message content).
    fn get_pending_supabase_messages(&self, limit: usize) -> Vec<PendingSupabaseMessage>;

    // ========================================================================
    // Supabase sync state operations (cursor-based)
    // ========================================================================

    /// Gets the Supabase sync state for a session.
    fn get_supabase_sync_state(&self, session: &SessionId) -> Option<SupabaseSyncState>;

    /// Gets sessions with pending messages to sync (cursor-based).
    fn get_sessions_pending_sync(&self, limit_per_session: usize) -> Vec<SessionPendingSync>;
}
