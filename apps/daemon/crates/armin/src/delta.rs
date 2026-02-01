//! Delta store for the Armin session engine.
//!
//! Deltas provide append-only views of messages added after a snapshot.
//!
//! # Design Principles
//!
//! - Deltas are derived from SQLite
//! - Deltas are append-only (new messages are added, never removed)
//! - Reads from deltas never cause side-effects

use std::collections::HashMap;
use std::sync::RwLock;

use crate::types::{Message, MessageId, SessionId};

/// A view of messages appended since the last snapshot.
#[derive(Debug, Clone)]
pub struct DeltaView {
    messages: Vec<Message>,
}

impl DeltaView {
    /// Creates a new empty delta view.
    pub fn empty() -> Self {
        Self {
            messages: Vec::new(),
        }
    }

    /// Creates a delta view from a list of messages.
    pub fn new(messages: Vec<Message>) -> Self {
        Self { messages }
    }

    /// Returns an iterator over the messages in the delta.
    pub fn iter(&self) -> impl Iterator<Item = &Message> {
        self.messages.iter()
    }

    /// Returns the number of messages in the delta.
    pub fn len(&self) -> usize {
        self.messages.len()
    }

    /// Returns true if the delta is empty.
    pub fn is_empty(&self) -> bool {
        self.messages.is_empty()
    }

    /// Returns all messages in the delta.
    pub fn messages(&self) -> &[Message] {
        &self.messages
    }
}

impl IntoIterator for DeltaView {
    type Item = Message;
    type IntoIter = std::vec::IntoIter<Message>;

    fn into_iter(self) -> Self::IntoIter {
        self.messages.into_iter()
    }
}

/// Stores deltas for all sessions.
///
/// Thread-safe and supports concurrent reads with exclusive writes.
#[derive(Debug)]
pub struct DeltaStore {
    /// Map of session ID to (last snapshot message ID, messages since snapshot)
    deltas: RwLock<HashMap<SessionId, SessionDelta>>,
}

/// Delta state for a single session.
#[derive(Debug, Clone)]
struct SessionDelta {
    /// The message ID at which the snapshot was taken (or None if no messages yet)
    snapshot_cursor: Option<MessageId>,
    /// Messages appended since the snapshot
    messages: Vec<Message>,
}

impl DeltaStore {
    /// Creates a new empty delta store.
    pub fn new() -> Self {
        Self {
            deltas: RwLock::new(HashMap::new()),
        }
    }

    /// Initializes a session's delta tracking.
    ///
    /// Call this during recovery to set up the snapshot cursor.
    pub fn init_session(&self, session: SessionId, last_message_id: Option<MessageId>) {
        let mut deltas = self.deltas.write().expect("lock poisoned");
        deltas.insert(
            session,
            SessionDelta {
                snapshot_cursor: last_message_id,
                messages: Vec::new(),
            },
        );
    }

    /// Appends a message to a session's delta.
    ///
    /// This should be called after the message is committed to SQLite.
    pub fn append(&self, session: SessionId, message: Message) {
        let mut deltas = self.deltas.write().expect("lock poisoned");
        let delta = deltas.entry(session).or_insert_with(|| SessionDelta {
            snapshot_cursor: None,
            messages: Vec::new(),
        });
        delta.messages.push(message);
    }

    /// Gets the delta view for a session.
    pub fn get(&self, session: SessionId) -> DeltaView {
        let deltas = self.deltas.read().expect("lock poisoned");
        deltas
            .get(&session)
            .map(|d| DeltaView::new(d.messages.clone()))
            .unwrap_or_else(DeltaView::empty)
    }

    /// Clears the delta for a session (e.g., after taking a new snapshot).
    pub fn clear(&self, session: SessionId) {
        let mut deltas = self.deltas.write().expect("lock poisoned");
        if let Some(delta) = deltas.get_mut(&session) {
            // Update the cursor to the last message
            if let Some(last) = delta.messages.last() {
                delta.snapshot_cursor = Some(last.id);
            }
            delta.messages.clear();
        }
    }

    /// Removes a session's delta tracking entirely.
    pub fn remove(&self, session: SessionId) {
        let mut deltas = self.deltas.write().expect("lock poisoned");
        deltas.remove(&session);
    }
}

impl Default for DeltaStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Role;

    fn make_message(id: u64, content: &str) -> Message {
        Message {
            id: MessageId(id),
            role: Role::User,
            content: content.to_string(),
        }
    }

    #[test]
    fn empty_delta() {
        let view = DeltaView::empty();
        assert!(view.is_empty());
        assert_eq!(view.len(), 0);
    }

    #[test]
    fn delta_with_messages() {
        let messages = vec![make_message(1, "Hello"), make_message(2, "World")];
        let view = DeltaView::new(messages);

        assert!(!view.is_empty());
        assert_eq!(view.len(), 2);

        let collected: Vec<_> = view.iter().collect();
        assert_eq!(collected[0].content, "Hello");
        assert_eq!(collected[1].content, "World");
    }

    #[test]
    fn delta_store_append_and_get() {
        let store = DeltaStore::new();
        let session = SessionId(1);

        store.append(session, make_message(1, "First"));
        store.append(session, make_message(2, "Second"));

        let delta = store.get(session);
        assert_eq!(delta.len(), 2);
        assert_eq!(delta.messages()[0].content, "First");
        assert_eq!(delta.messages()[1].content, "Second");
    }

    #[test]
    fn delta_store_clear() {
        let store = DeltaStore::new();
        let session = SessionId(1);

        store.append(session, make_message(1, "Message"));
        assert_eq!(store.get(session).len(), 1);

        store.clear(session);
        assert!(store.get(session).is_empty());
    }

    #[test]
    fn delta_store_remove() {
        let store = DeltaStore::new();
        let session = SessionId(1);

        store.init_session(session, None);
        store.append(session, make_message(1, "Message"));
        assert_eq!(store.get(session).len(), 1);

        store.remove(session);
        assert!(store.get(session).is_empty());
    }

    #[test]
    fn delta_store_multiple_sessions() {
        let store = DeltaStore::new();

        store.append(SessionId(1), make_message(1, "Session 1"));
        store.append(SessionId(2), make_message(2, "Session 2"));

        assert_eq!(store.get(SessionId(1)).len(), 1);
        assert_eq!(store.get(SessionId(2)).len(), 1);
        assert_eq!(store.get(SessionId(1)).messages()[0].content, "Session 1");
        assert_eq!(store.get(SessionId(2)).messages()[0].content, "Session 2");
    }
}
