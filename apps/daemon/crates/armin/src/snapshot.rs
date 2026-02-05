//! Snapshot views for the Armin session engine.
//!
//! Snapshots provide immutable views of session state at a point in time.
//!
//! # Design Principles
//!
//! - Snapshots are derived from SQLite on startup
//! - Snapshots are immutable after creation
//! - Reads from snapshots never cause side-effects

use std::collections::HashMap;
use std::sync::Arc;

use crate::types::{Message, SessionId};

/// An immutable snapshot of all sessions.
#[derive(Debug, Clone)]
pub struct SnapshotView {
    sessions: Arc<HashMap<SessionId, SessionSnapshot>>,
}

impl SnapshotView {
    /// Creates a new empty snapshot with no sessions.
    ///
    /// Returns a SnapshotView backed by an empty Arc-wrapped HashMap,
    /// representing a state with no existing sessions.
    pub fn empty() -> Self {
        Self {
            sessions: Arc::new(HashMap::new()),
        }
    }

    /// Creates a snapshot from an existing map of session snapshots.
    ///
    /// Wraps the provided HashMap in an Arc for efficient cloning and sharing
    /// across threads without copying the underlying data.
    pub fn new(sessions: HashMap<SessionId, SessionSnapshot>) -> Self {
        Self {
            sessions: Arc::new(sessions),
        }
    }

    /// Retrieves a reference to a session snapshot by its ID.
    ///
    /// Returns Some reference to the SessionSnapshot if found, or None if the
    /// session doesn't exist in this snapshot.
    pub fn session(&self, id: &SessionId) -> Option<&SessionSnapshot> {
        self.sessions.get(id)
    }

    /// Returns an iterator over all session IDs in the snapshot.
    ///
    /// Provides a way to enumerate available sessions without loading their
    /// full snapshot data.
    pub fn session_ids(&self) -> impl Iterator<Item = &SessionId> + '_ {
        self.sessions.keys()
    }

    /// Returns the total number of sessions in the snapshot.
    ///
    /// Provides a quick count without iterating through all sessions.
    pub fn len(&self) -> usize {
        self.sessions.len()
    }

    /// Checks if the snapshot contains no sessions.
    ///
    /// Returns true for a fresh or empty state, useful for early-exit checks.
    pub fn is_empty(&self) -> bool {
        self.sessions.is_empty()
    }
}

/// An immutable snapshot of a single session.
#[derive(Debug, Clone)]
pub struct SessionSnapshot {
    id: SessionId,
    messages: Vec<Message>,
    closed: bool,
}

impl SessionSnapshot {
    /// Creates a new immutable session snapshot.
    ///
    /// Captures the session's state at a point in time including all messages
    /// and the closed status. Once created, the snapshot cannot be modified.
    pub fn new(id: SessionId, messages: Vec<Message>, closed: bool) -> Self {
        Self {
            id,
            messages,
            closed,
        }
    }

    /// Returns a reference to the session's unique identifier.
    ///
    /// Provides access to the ID without cloning for comparisons and lookups.
    pub fn id(&self) -> &SessionId {
        &self.id
    }

    /// Returns a slice of all messages captured in this snapshot.
    ///
    /// Messages are ordered by their sequence number as they were at snapshot time.
    pub fn messages(&self) -> &[Message] {
        &self.messages
    }

    /// Checks if the session was closed at snapshot time.
    ///
    /// Returns true if the session had a non-active status (archived/deleted)
    /// when the snapshot was taken.
    pub fn is_closed(&self) -> bool {
        self.closed
    }

    /// Returns the count of messages in the session snapshot.
    ///
    /// Provides a quick way to check message volume without iterating.
    pub fn message_count(&self) -> usize {
        self.messages.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::MessageId;

    #[test]
    fn empty_snapshot() {
        let snapshot = SnapshotView::empty();
        assert!(snapshot.is_empty());
        assert_eq!(snapshot.len(), 0);
        assert!(snapshot.session(&SessionId::from_string("1")).is_none());
    }

    #[test]
    fn snapshot_with_sessions() {
        let session1_id = SessionId::from_string("session-1");
        let session2_id = SessionId::from_string("session-2");

        let mut sessions = HashMap::new();
        sessions.insert(
            session1_id.clone(),
            SessionSnapshot::new(
                session1_id.clone(),
                vec![Message {
                    id: MessageId::from_string("msg-1"),
                    content: "Hello".to_string(),
                    sequence_number: 0,
                }],
                false,
            ),
        );
        sessions.insert(
            session2_id.clone(),
            SessionSnapshot::new(session2_id.clone(), vec![], true),
        );

        let snapshot = SnapshotView::new(sessions);
        assert_eq!(snapshot.len(), 2);

        let session1 = snapshot.session(&session1_id).unwrap();
        assert_eq!(session1.id(), &session1_id);
        assert_eq!(session1.message_count(), 1);
        assert!(!session1.is_closed());

        let session2 = snapshot.session(&session2_id).unwrap();
        assert_eq!(session2.id(), &session2_id);
        assert_eq!(session2.message_count(), 0);
        assert!(session2.is_closed());
    }

    #[test]
    fn session_ids_iterator() {
        let session1_id = SessionId::from_string("session-1");
        let session2_id = SessionId::from_string("session-2");

        let mut sessions = HashMap::new();
        sessions.insert(session1_id.clone(), SessionSnapshot::new(session1_id.clone(), vec![], false));
        sessions.insert(session2_id.clone(), SessionSnapshot::new(session2_id.clone(), vec![], false));

        let snapshot = SnapshotView::new(sessions);
        let ids: Vec<_> = snapshot.session_ids().collect();
        assert_eq!(ids.len(), 2);
        assert!(ids.contains(&&session1_id));
        assert!(ids.contains(&&session2_id));
    }
}
