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
use crate::types::{Message, MessageId, NewMessage, SessionId};
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

        // Load all sessions
        let sessions = self.sqlite.list_sessions()?;
        tracing::debug!("armin: found {} sessions", sessions.len());

        // Build snapshot and initialize deltas
        let mut snapshot_sessions = HashMap::new();

        for session in sessions {
            // Load messages for this session
            let messages = self.sqlite.get_messages(session.id)?;
            let last_message_id = messages.last().map(|m| m.id);

            // Initialize delta tracking with cursor at end of current messages
            self.delta.init_session(session.id, last_message_id);

            // Create snapshot
            snapshot_sessions.insert(
                session.id,
                SessionSnapshot::new(session.id, messages, session.closed),
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
        let sessions = self.sqlite.list_sessions()?;
        let mut snapshot_sessions = HashMap::new();

        for session in sessions {
            let messages = self.sqlite.get_messages(session.id)?;

            // Clear delta and update cursor
            self.delta.clear(session.id);

            snapshot_sessions.insert(
                session.id,
                SessionSnapshot::new(session.id, messages, session.closed),
            );
        }

        *self.snapshot.write().expect("lock poisoned") = SnapshotView::new(snapshot_sessions);
        Ok(())
    }
}

impl<S: SideEffectSink> SessionWriter for Armin<S> {
    fn create_session(&self) -> SessionId {
        // 1. Commit fact to SQLite
        let session_id = self
            .sqlite
            .create_session()
            .expect("failed to create session");

        // 2. Update derived state
        self.delta.init_session(session_id, None);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::SessionCreated { session_id });

        session_id
    }

    fn append(&self, session: SessionId, message: NewMessage) -> MessageId {
        // Verify session exists and is open
        if !self
            .sqlite
            .is_session_open(session)
            .expect("failed to check session")
        {
            panic!("session {} does not exist or is closed", session.0);
        }

        // 1. Commit fact to SQLite
        let message_id = self
            .sqlite
            .insert_message(session, &message)
            .expect("failed to insert message");

        let full_message = Message {
            id: message_id,
            role: message.role,
            content: message.content,
        };

        // 2. Update derived state
        self.delta.append(session, full_message.clone());
        self.live.notify(session, full_message);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::MessageAppended {
            session_id: session,
            message_id,
        });

        message_id
    }

    fn close(&self, session: SessionId) {
        // 1. Commit fact to SQLite
        let closed = self
            .sqlite
            .close_session(session)
            .expect("failed to close session");

        if !closed {
            return; // Session didn't exist
        }

        // 2. Update derived state
        self.live.close_session(session);

        // 3. Emit side-effect
        self.sink.emit(SideEffect::SessionClosed { session_id: session });
    }
}

impl<S: SideEffectSink> SessionReader for Armin<S> {
    fn snapshot(&self) -> SnapshotView {
        self.snapshot.read().expect("lock poisoned").clone()
    }

    fn delta(&self, session: SessionId) -> DeltaView {
        self.delta.get(session)
    }

    fn subscribe(&self, session: SessionId) -> LiveSubscription {
        self.live.subscribe(session)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::side_effect::RecordingSink;
    use crate::types::Role;

    #[test]
    fn create_session_emits_side_effect() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(effects[0], SideEffect::SessionCreated { session_id });
    }

    #[test]
    fn append_message_emits_side_effect() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        armin.sink().clear();

        let message_id = armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: "Hello".to_string(),
            },
        );

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(
            effects[0],
            SideEffect::MessageAppended {
                session_id,
                message_id
            }
        );
    }

    #[test]
    fn close_session_emits_side_effect() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        armin.sink().clear();

        armin.close(session_id);

        let effects = armin.sink().effects();
        assert_eq!(effects.len(), 1);
        assert_eq!(effects[0], SideEffect::SessionClosed { session_id });
    }

    #[test]
    fn delta_contains_appended_messages() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: "First".to_string(),
            },
        );
        armin.append(
            session_id,
            NewMessage {
                role: Role::Assistant,
                content: "Second".to_string(),
            },
        );

        let delta = armin.delta(session_id);
        assert_eq!(delta.len(), 2);
        assert_eq!(delta.messages()[0].content, "First");
        assert_eq!(delta.messages()[1].content, "Second");
    }

    #[test]
    fn live_subscription_receives_messages() {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();

        let session_id = armin.create_session();
        let sub = armin.subscribe(session_id);

        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
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
        armin.close(session_id);

        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
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
            session_id,
            NewMessage {
                role: Role::User,
                content: "Message".to_string(),
            },
        );

        // Before refresh, snapshot doesn't include the new session
        // (it was created after initial recovery)
        armin.refresh_snapshot().unwrap();

        let snapshot = armin.snapshot();
        let session = snapshot.session(session_id).unwrap();
        assert_eq!(session.message_count(), 1);
        assert_eq!(session.messages()[0].content, "Message");
    }
}
