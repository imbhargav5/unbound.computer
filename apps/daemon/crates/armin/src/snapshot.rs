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
    /// Creates a new empty snapshot.
    pub fn empty() -> Self {
        Self {
            sessions: Arc::new(HashMap::new()),
        }
    }

    /// Creates a snapshot from a map of sessions.
    pub fn new(sessions: HashMap<SessionId, SessionSnapshot>) -> Self {
        Self {
            sessions: Arc::new(sessions),
        }
    }

    /// Gets a session by ID.
    pub fn session(&self, id: SessionId) -> Option<&SessionSnapshot> {
        self.sessions.get(&id)
    }

    /// Returns an iterator over all session IDs.
    pub fn session_ids(&self) -> impl Iterator<Item = SessionId> + '_ {
        self.sessions.keys().copied()
    }

    /// Returns the number of sessions in the snapshot.
    pub fn len(&self) -> usize {
        self.sessions.len()
    }

    /// Returns true if the snapshot is empty.
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
    /// Creates a new session snapshot.
    pub fn new(id: SessionId, messages: Vec<Message>, closed: bool) -> Self {
        Self {
            id,
            messages,
            closed,
        }
    }

    /// Returns the session ID.
    pub fn id(&self) -> SessionId {
        self.id
    }

    /// Returns all messages in the session.
    pub fn messages(&self) -> &[Message] {
        &self.messages
    }

    /// Returns true if the session is closed.
    pub fn is_closed(&self) -> bool {
        self.closed
    }

    /// Returns the number of messages in the session.
    pub fn message_count(&self) -> usize {
        self.messages.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{MessageId, Role};

    #[test]
    fn empty_snapshot() {
        let snapshot = SnapshotView::empty();
        assert!(snapshot.is_empty());
        assert_eq!(snapshot.len(), 0);
        assert!(snapshot.session(SessionId(1)).is_none());
    }

    #[test]
    fn snapshot_with_sessions() {
        let mut sessions = HashMap::new();
        sessions.insert(
            SessionId(1),
            SessionSnapshot::new(
                SessionId(1),
                vec![Message {
                    id: MessageId(1),
                    role: Role::User,
                    content: "Hello".to_string(),
                }],
                false,
            ),
        );
        sessions.insert(
            SessionId(2),
            SessionSnapshot::new(SessionId(2), vec![], true),
        );

        let snapshot = SnapshotView::new(sessions);
        assert_eq!(snapshot.len(), 2);

        let session1 = snapshot.session(SessionId(1)).unwrap();
        assert_eq!(session1.id(), SessionId(1));
        assert_eq!(session1.message_count(), 1);
        assert!(!session1.is_closed());

        let session2 = snapshot.session(SessionId(2)).unwrap();
        assert_eq!(session2.id(), SessionId(2));
        assert_eq!(session2.message_count(), 0);
        assert!(session2.is_closed());
    }

    #[test]
    fn session_ids_iterator() {
        let mut sessions = HashMap::new();
        sessions.insert(SessionId(1), SessionSnapshot::new(SessionId(1), vec![], false));
        sessions.insert(SessionId(2), SessionSnapshot::new(SessionId(2), vec![], false));

        let snapshot = SnapshotView::new(sessions);
        let ids: Vec<_> = snapshot.session_ids().collect();
        assert_eq!(ids.len(), 2);
        assert!(ids.contains(&SessionId(1)));
        assert!(ids.contains(&SessionId(2)));
    }
}
