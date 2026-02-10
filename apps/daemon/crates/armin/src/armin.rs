//! The Armin engine - the brain of the session engine.
//!
//! Armin coordinates writes, derived state, and side-effects.
//!
//! # Write Path (strict order)
//!
//! 1. Commit fact to SQLite
//! 2. Update derived state (delta, live)
//! 3. Emit side-effect
//!
//! If step 1 fails, nothing else runs.
//! Side-effects always observe committed state.
//!
//! # Recovery (silent)
//!
//! On startup:
//! 1. Open SQLite
//! 2. Load sessions
//! 3. Rebuild deltas
//! 4. Serve reads
//!
//! Recovery emits NO side-effects and NO live notifications.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;

use crate::delta::{DeltaStore, DeltaView};
use crate::live::{LiveHub, LiveSubscription};
use crate::reader::SessionReader;
use crate::side_effect::{SideEffect, SideEffectSink};
use crate::snapshot::{SessionSnapshot, SnapshotView};
use crate::sqlite::SqliteStore;
use crate::types::{
    AblySyncState, AgentStatus, Message, MessageId, NewMessage, NewRepository, NewSession,
    NewSessionSecret, PendingSupabaseMessage, Repository, RepositoryId, Session, SessionId,
    SessionPendingSync, SessionSecret, SessionState, SessionStatus, SessionUpdate,
    SupabaseSyncState,
};
use crate::writer::SessionWriter;
use crate::ArminError;

/// The Armin session engine.
///
/// Coordinates SQLite storage, derived state, and side-effects.
pub struct Armin<S: SideEffectSink> {
    sqlite: SqliteStore,
    delta: DeltaStore,
    live: LiveHub,
    sink: Arc<S>,
    /// Cached snapshot (rebuilt on startup, refreshed on demand)
    snapshot: std::sync::RwLock<SnapshotView>,
}

impl<S: SideEffectSink> Armin<S> {
    /// Opens an Armin engine with a SQLite database at the given path.
    ///
    /// This performs recovery: it loads all sessions and messages from SQLite
    /// and rebuilds derived state. No side-effects are emitted during recovery.
    pub fn open(path: impl AsRef<Path>, sink: S) -> Result<Self, ArminError> {
        let sqlite = SqliteStore::open(path)?;
        Self::from_sqlite(sqlite, sink)
    }

    /// Creates an Armin engine with an in-memory SQLite database.
    ///
    /// Useful for testing.
    pub fn in_memory(sink: S) -> Result<Self, ArminError> {
        let sqlite = SqliteStore::in_memory()?;
        Self::from_sqlite(sqlite, sink)
    }

    /// Creates an Armin engine from an existing SQLite store.
    fn from_sqlite(sqlite: SqliteStore, sink: S) -> Result<Self, ArminError> {
        let delta = DeltaStore::new();
        let live = LiveHub::new();

        let engine = Self {
            sqlite,
            delta,
            live,
            sink: Arc::new(sink),
            snapshot: std::sync::RwLock::new(SnapshotView::empty()),
        };

        // Perform recovery (no side-effects)
        engine.recover()?;

        Ok(engine)
    }

    /// Recovers state from SQLite.
    ///
    /// This is called on startup and does NOT emit side-effects or live notifications.
    fn recover(&self) -> Result<(), ArminError> {
        tracing::info!("armin: starting recovery from SQLite");

        // Load all sessions from agent_coding_sessions table
        let sessions = self.sqlite.list_all_agent_sessions()?;
        tracing::debug!("armin: found {} sessions", sessions.len());

        // Build snapshot and initialize deltas
        let mut snapshot_sessions = HashMap::new();

        for session in sessions {
            // Load messages for this session
            let messages = self.sqlite.get_agent_messages(&session.id)?;
            let last_message_id = messages.last().map(|m| m.id.clone());

            // Initialize delta tracking with cursor at end of current messages
            self.delta.init_session(session.id.clone(), last_message_id);

            // Sessions are "closed" if status is not active
            let closed = session.status != crate::types::SessionStatus::Active;

            // Create snapshot
            snapshot_sessions.insert(
                session.id.clone(),
                SessionSnapshot::new(session.id.clone(), messages, closed),
            );
        }

        // Update snapshot
        *self.snapshot.write().expect("lock poisoned") = SnapshotView::new(snapshot_sessions);

        tracing::info!("armin: recovery complete");
        Ok(())
    }

    /// Returns a reference to the side-effect sink.
    pub fn sink(&self) -> &S {
        &self.sink
    }

    /// Refreshes the snapshot from current state.
    ///
    /// This rebuilds the snapshot from SQLite and clears all deltas.
    pub fn refresh_snapshot(&self) -> Result<(), ArminError> {
        let sessions = self.sqlite.list_all_agent_sessions()?;
        let mut snapshot_sessions = HashMap::new();

        for session in sessions {
            let messages = self.sqlite.get_agent_messages(&session.id)?;

            // Clear delta and update cursor
            self.delta.clear(&session.id);

            let closed = session.status != crate::types::SessionStatus::Active;

            snapshot_sessions.insert(
                session.id.clone(),
                SessionSnapshot::new(session.id.clone(), messages, closed),
            );
        }

        *self.snapshot.write().expect("lock poisoned") = SnapshotView::new(snapshot_sessions);
        Ok(())
    }
}

impl<S: SideEffectSink> SessionWriter for Armin<S> {
    // ========================================================================
    // Repository operations
    // ========================================================================

    fn create_repository(&self, repo: NewRepository) -> Result<Repository, ArminError> {
        // 1. Commit fact to SQLite
        let repository = self.sqlite.insert_repository(&repo)?;

        // 2. No derived state for repositories

        // 3. Emit side-effect
        self.sink.emit(SideEffect::RepositoryCreated {
            repository_id: repository.id.clone(),
        });

        Ok(repository)
    }

    fn delete_repository(&self, id: &RepositoryId) -> Result<bool, ArminError> {
        // 1. Commit fact to SQLite
        let deleted = self.sqlite.delete_repository(id)?;

        if deleted {
            // 3. Emit side-effect
            self.sink.emit(SideEffect::RepositoryDeleted {
                repository_id: id.clone(),
            });
        }

        Ok(deleted)
    }

    // ========================================================================
    // Session operations (full metadata)
    // ========================================================================

    fn create_session_with_metadata(&self, session: NewSession) -> Result<Session, ArminError> {
        // 1. Commit fact to SQLite
        let created = self.sqlite.insert_agent_session(&session)?;

        // 2. Update derived state
        self.delta.init_session(created.id.clone(), None);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::SessionCreated {
            session_id: created.id.clone(),
        });

        Ok(created)
    }

    fn update_session(&self, id: &SessionId, update: SessionUpdate) -> Result<bool, ArminError> {
        // 1. Commit fact to SQLite
        let updated = self.sqlite.update_agent_session(id, &update)?;

        if updated {
            // 3. Emit side-effect
            self.sink.emit(SideEffect::SessionUpdated {
                session_id: id.clone(),
            });
        }

        Ok(updated)
    }

    fn update_session_claude_id(
        &self,
        id: &SessionId,
        claude_session_id: &str,
    ) -> Result<bool, ArminError> {
        // 1. Commit fact to SQLite
        let updated = self
            .sqlite
            .update_agent_session_claude_id(id, claude_session_id)?;

        if updated {
            // 3. Emit side-effect
            self.sink.emit(SideEffect::SessionUpdated {
                session_id: id.clone(),
            });
        }

        Ok(updated)
    }

    fn delete_session(&self, id: &SessionId) -> Result<bool, ArminError> {
        // 1. Commit fact to SQLite
        let deleted = self.sqlite.delete_agent_session(id)?;

        if deleted {
            // 2. Update derived state
            self.live.close_session(id);
            self.delta.clear(id);

            // 3. Emit side-effect
            self.sink.emit(SideEffect::SessionDeleted {
                session_id: id.clone(),
            });
        }

        Ok(deleted)
    }

    // ========================================================================
    // Session state operations
    // ========================================================================

    fn update_agent_status(
        &self,
        session: &SessionId,
        status: AgentStatus,
    ) -> Result<(), ArminError> {
        // 1. Ensure session state exists, then update
        let _ = self.sqlite.get_or_create_session_state(session)?;

        let updated = self.sqlite.update_agent_status(session, status)?;

        if updated {
            // 3. Emit side-effect
            self.sink.emit(SideEffect::AgentStatusChanged {
                session_id: session.clone(),
                status,
            });
        }

        Ok(())
    }

    // ========================================================================
    // Simple session operations (for tests - creates default repository)
    // ========================================================================

    fn create_session(&self) -> Result<SessionId, ArminError> {
        // Ensure default repository exists for simple session creation
        let default_repo_id = RepositoryId::from_string("default-test-repo");
        if self.sqlite.get_repository(&default_repo_id).is_err()
            || self
                .sqlite
                .get_repository(&default_repo_id)
                .unwrap()
                .is_none()
        {
            let repo = NewRepository {
                id: default_repo_id.clone(),
                path: "/tmp/armin-test".to_string(),
                name: "Test Repository".to_string(),
                is_git_repository: false,
                sessions_path: None,
                default_branch: None,
                default_remote: None,
            };
            let _ = self.sqlite.insert_repository(&repo);
        }

        // Create session in agent_coding_sessions
        let session = NewSession {
            id: SessionId::new(),
            repository_id: default_repo_id,
            title: "Test Session".to_string(),
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        };

        let created = self.sqlite.insert_agent_session(&session)?;

        // 2. Update derived state
        self.delta.init_session(created.id.clone(), None);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::SessionCreated {
            session_id: created.id.clone(),
        });

        Ok(created.id)
    }

    fn append(&self, session: &SessionId, message: NewMessage) -> Result<Message, ArminError> {
        // Verify session exists and is active
        match self.sqlite.get_agent_session(session) {
            Ok(Some(s)) if s.status == SessionStatus::Active => {}
            _ => return Err(ArminError::SessionNotFound(session.0.clone())),
        }

        // 1. Commit fact to SQLite (atomic sequence assignment)
        let inserted = self.sqlite.insert_agent_message(session, &message)?;

        let full_message = Message {
            id: inserted.id.clone(),
            content: message.content,
            sequence_number: inserted.sequence_number,
        };

        // 2. Update derived state
        self.delta.append(session, full_message.clone());
        self.live.notify(session, full_message.clone());

        // 3. Emit side-effect
        self.sink.emit(SideEffect::MessageAppended {
            session_id: session.clone(),
            message_id: inserted.id,
            sequence_number: full_message.sequence_number,
            content: full_message.content.clone(),
        });

        Ok(full_message)
    }

    fn close(&self, session: &SessionId) -> Result<(), ArminError> {
        // Check if session exists and is currently active
        let current_session = match self.sqlite.get_agent_session(session) {
            Ok(Some(s)) => s,
            _ => return Ok(()), // Session doesn't exist - not an error
        };

        // Only close if currently active
        if current_session.status != SessionStatus::Active {
            return Ok(()); // Already closed - not an error
        }

        // 1. Update session status to Archived
        let update = SessionUpdate {
            title: None,
            status: Some(SessionStatus::Archived),
            claude_session_id: None,
            last_accessed_at: None,
        };
        self.sqlite.update_agent_session(session, &update)?;

        // 2. Update derived state
        self.live.close_session(session);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::SessionClosed {
            session_id: session.clone(),
        });

        Ok(())
    }

    // ========================================================================
    // Session secrets operations
    // ========================================================================

    fn set_session_secret(&self, secret: NewSessionSecret) -> Result<(), ArminError> {
        // 1. Commit fact to SQLite
        self.sqlite.set_session_secret(&secret)?;

        // 2. No derived state for secrets
        // 3. No side-effect for secrets (security consideration)
        Ok(())
    }

    fn delete_session_secret(&self, session: &SessionId) -> Result<bool, ArminError> {
        // 1. Commit fact to SQLite
        Ok(self.sqlite.delete_session_secret(session)?)
    }

    // ========================================================================
    // Supabase message outbox operations
    // ========================================================================

    fn insert_supabase_message_outbox(&self, message_id: &MessageId) -> Result<(), ArminError> {
        self.sqlite.insert_supabase_message_outbox(message_id)?;
        Ok(())
    }

    fn mark_supabase_messages_sent(&self, message_ids: &[MessageId]) -> Result<(), ArminError> {
        self.sqlite.mark_supabase_messages_sent(message_ids)?;
        Ok(())
    }

    fn mark_supabase_messages_failed(
        &self,
        message_ids: &[MessageId],
        error: &str,
    ) -> Result<(), ArminError> {
        self.sqlite
            .mark_supabase_messages_failed(message_ids, error)?;
        Ok(())
    }

    fn delete_supabase_message_outbox(&self, message_ids: &[MessageId]) -> Result<(), ArminError> {
        self.sqlite.delete_supabase_message_outbox(message_ids)?;
        Ok(())
    }

    // ========================================================================
    // Supabase sync state operations (cursor-based)
    // ========================================================================

    fn mark_supabase_sync_success(
        &self,
        session: &SessionId,
        up_to_sequence: i64,
    ) -> Result<(), ArminError> {
        self.sqlite
            .mark_supabase_sync_success(session, up_to_sequence)?;
        Ok(())
    }

    fn mark_supabase_sync_failed(
        &self,
        session: &SessionId,
        error: &str,
    ) -> Result<(), ArminError> {
        self.sqlite.mark_supabase_sync_failed(session, error)?;
        Ok(())
    }

    // ========================================================================
    // Ably sync state operations (cursor-based)
    // ========================================================================

    fn mark_ably_sync_success(
        &self,
        session: &SessionId,
        up_to_sequence: i64,
    ) -> Result<(), ArminError> {
        self.sqlite
            .mark_ably_sync_success(session, up_to_sequence)?;
        Ok(())
    }

    fn mark_ably_sync_failed(&self, session: &SessionId, error: &str) -> Result<(), ArminError> {
        self.sqlite.mark_ably_sync_failed(session, error)?;
        Ok(())
    }
}

impl<S: SideEffectSink> SessionReader for Armin<S> {
    // ========================================================================
    // Repository operations
    // ========================================================================

    fn list_repositories(&self) -> Result<Vec<Repository>, ArminError> {
        Ok(self.sqlite.list_repositories()?)
    }

    fn get_repository(&self, id: &RepositoryId) -> Result<Option<Repository>, ArminError> {
        Ok(self.sqlite.get_repository(id)?)
    }

    fn get_repository_by_path(&self, path: &str) -> Result<Option<Repository>, ArminError> {
        Ok(self.sqlite.get_repository_by_path(path)?)
    }

    // ========================================================================
    // Session operations (full metadata)
    // ========================================================================

    fn list_sessions(&self, repository_id: &RepositoryId) -> Result<Vec<Session>, ArminError> {
        Ok(self
            .sqlite
            .list_agent_sessions_for_repository(repository_id)?)
    }

    fn get_session(&self, id: &SessionId) -> Result<Option<Session>, ArminError> {
        Ok(self.sqlite.get_agent_session(id)?)
    }

    // ========================================================================
    // Session state operations
    // ========================================================================

    fn get_session_state(&self, session: &SessionId) -> Result<Option<SessionState>, ArminError> {
        Ok(self.sqlite.get_session_state(session)?)
    }

    // ========================================================================
    // Message snapshot/delta/live operations
    // ========================================================================

    fn snapshot(&self) -> SnapshotView {
        self.snapshot.read().expect("lock poisoned").clone()
    }

    fn delta(&self, session: &SessionId) -> DeltaView {
        self.delta.get(session)
    }

    fn subscribe(&self, session: &SessionId) -> LiveSubscription {
        self.live.subscribe(session)
    }

    // ========================================================================
    // Session secrets operations
    // ========================================================================

    fn get_session_secret(&self, session: &SessionId) -> Result<Option<SessionSecret>, ArminError> {
        Ok(self.sqlite.get_session_secret(session)?)
    }

    fn has_session_secret(&self, session: &SessionId) -> Result<bool, ArminError> {
        Ok(self.sqlite.has_session_secret(session)?)
    }

    // ========================================================================
    // Supabase message outbox operations
    // ========================================================================

    fn get_pending_supabase_messages(
        &self,
        limit: usize,
    ) -> Result<Vec<PendingSupabaseMessage>, ArminError> {
        Ok(self.sqlite.get_pending_supabase_messages(limit)?)
    }

    // ========================================================================
    // Supabase sync state operations (cursor-based)
    // ========================================================================

    fn get_supabase_sync_state(
        &self,
        session: &SessionId,
    ) -> Result<Option<SupabaseSyncState>, ArminError> {
        Ok(self.sqlite.get_supabase_sync_state(session)?)
    }

    fn get_sessions_pending_sync(
        &self,
        limit_per_session: usize,
    ) -> Result<Vec<SessionPendingSync>, ArminError> {
        Ok(self.sqlite.get_sessions_pending_sync(limit_per_session)?)
    }

    // ========================================================================
    // Ably sync state operations (cursor-based)
    // ========================================================================

    fn get_ably_sync_state(
        &self,
        session: &SessionId,
    ) -> Result<Option<AblySyncState>, ArminError> {
        Ok(self.sqlite.get_ably_sync_state(session)?)
    }

    fn get_sessions_pending_ably_sync(
        &self,
        limit_per_session: usize,
    ) -> Result<Vec<SessionPendingSync>, ArminError> {
        Ok(self
            .sqlite
            .get_sessions_pending_ably_sync(limit_per_session)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::side_effect::RecordingSink;

    #[test]
    fn create_session_emits_side_effect() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session().unwrap();

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(
            effects[0],
            SideEffect::SessionCreated {
                session_id: session_id.clone()
            }
        );
    }

    #[test]
    fn append_message_emits_side_effect() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session().unwrap();
        armin.sink().clear();

        let message = armin
            .append(
                &session_id,
                NewMessage {
                    content: "Hello".to_string(),
                },
            )
            .unwrap();

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(
            effects[0],
            SideEffect::MessageAppended {
                session_id: session_id.clone(),
                message_id: message.id.clone(),
                sequence_number: message.sequence_number,
                content: message.content.clone(),
            }
        );
    }

    #[test]
    fn close_session_emits_side_effect() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session().unwrap();
        armin.sink().clear();

        armin.close(&session_id).unwrap();

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(
            effects[0],
            SideEffect::SessionClosed {
                session_id: session_id.clone()
            }
        );
    }

    #[test]
    fn delta_contains_appended_messages() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session().unwrap();
        let msg1 = armin
            .append(
                &session_id,
                NewMessage {
                    content: "First".to_string(),
                },
            )
            .unwrap();
        let msg2 = armin
            .append(
                &session_id,
                NewMessage {
                    content: "Second".to_string(),
                },
            )
            .unwrap();

        // Verify sequence numbers are assigned correctly
        assert_eq!(msg1.sequence_number, 1);
        assert_eq!(msg2.sequence_number, 2);

        let delta = armin.delta(&session_id);
        assert_eq!(delta.len(), 2);
        assert_eq!(delta.messages()[0].content, "First");
        assert_eq!(delta.messages()[1].content, "Second");
    }

    #[test]
    fn live_subscription_receives_messages() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session().unwrap();
        let sub = armin.subscribe(&session_id);

        armin
            .append(
                &session_id,
                NewMessage {
                    content: "Hello".to_string(),
                },
            )
            .unwrap();

        let msg = sub.try_recv().unwrap();
        assert_eq!(msg.content, "Hello");
    }

    #[test]
    fn append_to_closed_session_returns_error() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session().unwrap();
        armin.close(&session_id).unwrap();

        let result = armin.append(
            &session_id,
            NewMessage {
                content: "Should fail".to_string(),
            },
        );
        assert!(result.is_err());
    }

    #[test]
    fn snapshot_after_refresh() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session().unwrap();
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "Message".to_string(),
                },
            )
            .unwrap();

        // Before refresh, snapshot doesn't include the new session
        // (it was created after initial recovery)
        armin.refresh_snapshot().unwrap();

        let snapshot = armin.snapshot();
        let session = snapshot.session(&session_id).unwrap();
        assert_eq!(session.message_count(), 1);
        assert_eq!(session.messages()[0].content, "Message");
    }
}
