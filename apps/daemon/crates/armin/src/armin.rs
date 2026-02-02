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
    AgentStatus, Message, NewMessage, NewOutboxEvent, NewRepository, NewSession,
    NewSessionSecret, OutboxEvent, Repository, RepositoryId, Session, SessionId,
    SessionSecret, SessionState, SessionStatus, SessionUpdate,
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

    fn create_repository(&self, repo: NewRepository) -> Repository {
        // 1. Commit fact to SQLite
        let repository = self
            .sqlite
            .insert_repository(&repo)
            .expect("failed to create repository");

        // 2. No derived state for repositories

        // 3. Emit side-effect
        self.sink.emit(SideEffect::RepositoryCreated {
            repository_id: repository.id.clone(),
        });

        repository
    }

    fn delete_repository(&self, id: &RepositoryId) -> bool {
        // 1. Commit fact to SQLite
        let deleted = self
            .sqlite
            .delete_repository(id)
            .expect("failed to delete repository");

        if deleted {
            // 3. Emit side-effect
            self.sink.emit(SideEffect::RepositoryDeleted {
                repository_id: id.clone(),
            });
        }

        deleted
    }

    // ========================================================================
    // Session operations (full metadata)
    // ========================================================================

    fn create_session_with_metadata(&self, session: NewSession) -> Session {
        // 1. Commit fact to SQLite
        let created = self
            .sqlite
            .insert_agent_session(&session)
            .expect("failed to create session");

        // 2. Update derived state
        self.delta.init_session(created.id.clone(), None);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::SessionCreated {
            session_id: created.id.clone(),
        });

        created
    }

    fn update_session(&self, id: &SessionId, update: SessionUpdate) -> bool {
        // 1. Commit fact to SQLite
        let updated = self
            .sqlite
            .update_agent_session(id, &update)
            .expect("failed to update session");

        if updated {
            // 3. Emit side-effect
            self.sink.emit(SideEffect::SessionUpdated {
                session_id: id.clone(),
            });
        }

        updated
    }

    fn update_session_claude_id(&self, id: &SessionId, claude_session_id: &str) -> bool {
        // 1. Commit fact to SQLite
        let updated = self
            .sqlite
            .update_agent_session_claude_id(id, claude_session_id)
            .expect("failed to update claude session id");

        if updated {
            // 3. Emit side-effect
            self.sink.emit(SideEffect::SessionUpdated {
                session_id: id.clone(),
            });
        }

        updated
    }

    fn delete_session(&self, id: &SessionId) -> bool {
        // 1. Commit fact to SQLite
        let deleted = self
            .sqlite
            .delete_agent_session(id)
            .expect("failed to delete session");

        if deleted {
            // 2. Update derived state
            self.live.close_session(id);
            self.delta.clear(id);

            // 3. Emit side-effect
            self.sink.emit(SideEffect::SessionDeleted {
                session_id: id.clone(),
            });
        }

        deleted
    }

    // ========================================================================
    // Session state operations
    // ========================================================================

    fn update_agent_status(&self, session: &SessionId, status: AgentStatus) {
        // 1. Ensure session state exists, then update
        let _ = self.sqlite.get_or_create_session_state(session)
            .expect("failed to get or create session state");

        let updated = self
            .sqlite
            .update_agent_status(session, status)
            .expect("failed to update agent status");

        if updated {
            // 3. Emit side-effect
            self.sink.emit(SideEffect::AgentStatusChanged {
                session_id: session.clone(),
                status,
            });
        }
    }

    // ========================================================================
    // Simple session operations (for tests - creates default repository)
    // ========================================================================

    fn create_session(&self) -> SessionId {
        // Ensure default repository exists for simple session creation
        let default_repo_id = RepositoryId::from_string("default-test-repo");
        if self.sqlite.get_repository(&default_repo_id).is_err()
            || self.sqlite.get_repository(&default_repo_id).unwrap().is_none()
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

        let created = self.sqlite
            .insert_agent_session(&session)
            .expect("failed to create session");

        // 2. Update derived state
        self.delta.init_session(created.id.clone(), None);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::SessionCreated { session_id: created.id.clone() });

        created.id
    }

    fn append(&self, session: &SessionId, message: NewMessage) -> Message {
        // Verify session exists and is active
        match self.sqlite.get_agent_session(session) {
            Ok(Some(s)) if s.status == SessionStatus::Active => {}
            Ok(Some(_)) => panic!("session {} does not exist or is closed", session.0),
            _ => panic!("session {} does not exist or is closed", session.0),
        }

        // 1. Commit fact to SQLite (atomic sequence assignment)
        let inserted = self.sqlite
            .insert_agent_message(session, &message)
            .expect("failed to insert message");

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
        });

        full_message
    }

    fn close(&self, session: &SessionId) {
        // Check if session exists and is currently active
        let current_session = match self.sqlite.get_agent_session(session) {
            Ok(Some(s)) => s,
            _ => return, // Session doesn't exist
        };

        // Only close if currently active
        if current_session.status != SessionStatus::Active {
            return; // Already closed
        }

        // 1. Update session status to Archived
        let update = SessionUpdate {
            title: None,
            status: Some(SessionStatus::Archived),
            claude_session_id: None,
            last_accessed_at: None,
        };
        self.sqlite
            .update_agent_session(session, &update)
            .expect("failed to close session");

        // 2. Update derived state
        self.live.close_session(session);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::SessionClosed { session_id: session.clone() });
    }

    // ========================================================================
    // Session secrets operations
    // ========================================================================

    fn set_session_secret(&self, secret: NewSessionSecret) {
        // 1. Commit fact to SQLite
        self.sqlite
            .set_session_secret(&secret)
            .expect("failed to set session secret");

        // 2. No derived state for secrets
        // 3. No side-effect for secrets (security consideration)
    }

    fn delete_session_secret(&self, session: &SessionId) -> bool {
        // 1. Commit fact to SQLite
        self.sqlite
            .delete_session_secret(session)
            .expect("failed to delete session secret")
    }

    // ========================================================================
    // Outbox operations
    // ========================================================================

    fn insert_outbox_event(&self, event: NewOutboxEvent) -> OutboxEvent {
        // 1. Commit fact to SQLite
        self.sqlite
            .insert_outbox_event(&event)
            .expect("failed to insert outbox event");

        // Return a constructed OutboxEvent
        OutboxEvent {
            event_id: event.event_id,
            session_id: event.session_id,
            sequence_number: event.sequence_number,
            relay_send_batch_id: None,
            message_id: event.message_id,
            status: crate::types::OutboxStatus::Pending,
            retry_count: 0,
            last_error: None,
            created_at: chrono::Utc::now(),
            sent_at: None,
            acked_at: None,
        }
    }

    fn mark_outbox_sent(&self, batch_id: &str, event_ids: &[String]) {
        // 1. Commit fact to SQLite
        self.sqlite
            .mark_outbox_events_sent(event_ids, batch_id)
            .expect("failed to mark outbox events sent");

        // 3. Emit side-effect
        self.sink.emit(SideEffect::OutboxEventsSent {
            batch_id: batch_id.to_string(),
        });
    }

    fn mark_outbox_acked(&self, batch_id: &str) {
        // 1. Commit fact to SQLite
        self.sqlite
            .mark_outbox_batch_acked(batch_id)
            .expect("failed to mark outbox batch acked");

        // 3. Emit side-effect
        self.sink.emit(SideEffect::OutboxEventsAcked {
            batch_id: batch_id.to_string(),
        });
    }
}

impl<S: SideEffectSink> SessionReader for Armin<S> {
    // ========================================================================
    // Repository operations
    // ========================================================================

    fn list_repositories(&self) -> Vec<Repository> {
        self.sqlite
            .list_repositories()
            .expect("failed to list repositories")
    }

    fn get_repository(&self, id: &RepositoryId) -> Option<Repository> {
        self.sqlite
            .get_repository(id)
            .expect("failed to get repository")
    }

    fn get_repository_by_path(&self, path: &str) -> Option<Repository> {
        self.sqlite
            .get_repository_by_path(path)
            .expect("failed to get repository by path")
    }

    // ========================================================================
    // Session operations (full metadata)
    // ========================================================================

    fn list_sessions(&self, repository_id: &RepositoryId) -> Vec<Session> {
        self.sqlite
            .list_agent_sessions_for_repository(repository_id)
            .expect("failed to list sessions")
    }

    fn get_session(&self, id: &SessionId) -> Option<Session> {
        self.sqlite
            .get_agent_session(id)
            .expect("failed to get session")
    }

    // ========================================================================
    // Session state operations
    // ========================================================================

    fn get_session_state(&self, session: &SessionId) -> Option<SessionState> {
        self.sqlite
            .get_session_state(session)
            .expect("failed to get session state")
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

    fn get_session_secret(&self, session: &SessionId) -> Option<SessionSecret> {
        self.sqlite
            .get_session_secret(session)
            .expect("failed to get session secret")
    }

    fn has_session_secret(&self, session: &SessionId) -> bool {
        self.sqlite
            .has_session_secret(session)
            .expect("failed to check session secret")
    }

    // ========================================================================
    // Outbox operations
    // ========================================================================

    fn get_pending_outbox_events(&self, session: &SessionId, limit: usize) -> Vec<OutboxEvent> {
        self.sqlite
            .get_pending_outbox_events(session, limit)
            .expect("failed to get pending outbox events")
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

        let session_id = armin.create_session();

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(effects[0], SideEffect::SessionCreated { session_id: session_id.clone() });
    }

    #[test]
    fn append_message_emits_side_effect() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        armin.sink().clear();

        let message = armin.append(
            &session_id,
            NewMessage {
                content: "Hello".to_string(),
            },
        );

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(
            effects[0],
            SideEffect::MessageAppended {
                session_id: session_id.clone(),
                message_id: message.id.clone()
            }
        );
    }

    #[test]
    fn close_session_emits_side_effect() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        armin.sink().clear();

        armin.close(&session_id);

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(effects[0], SideEffect::SessionClosed { session_id: session_id.clone() });
    }

    #[test]
    fn delta_contains_appended_messages() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        let msg1 = armin.append(
            &session_id,
            NewMessage {
                content: "First".to_string(),
            },
        );
        let msg2 = armin.append(
            &session_id,
            NewMessage {
                content: "Second".to_string(),
            },
        );

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

        let session_id = armin.create_session();
        let sub = armin.subscribe(&session_id);

        armin.append(
            &session_id,
            NewMessage {
                content: "Hello".to_string(),
            },
        );

        let msg = sub.try_recv().unwrap();
        assert_eq!(msg.content, "Hello");
    }

    #[test]
    #[should_panic(expected = "does not exist or is closed")]
    fn append_to_closed_session_panics() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        armin.close(&session_id);

        armin.append(
            &session_id,
            NewMessage {
                content: "Should fail".to_string(),
            },
        );
    }

    #[test]
    fn snapshot_after_refresh() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        armin.append(
            &session_id,
            NewMessage {
                content: "Message".to_string(),
            },
        );

        // Before refresh, snapshot doesn't include the new session
        // (it was created after initial recovery)
        armin.refresh_snapshot().unwrap();

        let snapshot = armin.snapshot();
        let session = snapshot.session(&session_id).unwrap();
        assert_eq!(session.message_count(), 1);
        assert_eq!(session.messages()[0].content, "Message");
    }
}
