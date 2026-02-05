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
    /// Creates a new empty delta view with no messages.
    ///
    /// Returns a DeltaView containing an empty vector, representing a session
    /// with no new messages since the last snapshot.
    pub fn empty() -> Self {
        Self {
            messages: Vec::new(),
        }
    }

    /// Creates a delta view from a pre-existing list of messages.
    ///
    /// Takes ownership of the message vector and wraps it in a DeltaView
    /// for consistent access patterns.
    pub fn new(messages: Vec<Message>) -> Self {
        Self { messages }
    }

    /// Returns a borrowing iterator over the messages in the delta.
    ///
    /// Allows iterating through messages without consuming the DeltaView,
    /// useful for read-only operations like rendering or filtering.
    pub fn iter(&self) -> impl Iterator<Item = &Message> {
        self.messages.iter()
    }

    /// Returns the count of messages in this delta view.
    ///
    /// Provides a quick way to check how many messages have been appended
    /// since the last snapshot without iterating.
    pub fn len(&self) -> usize {
        self.messages.len()
    }

    /// Checks if the delta contains no messages.
    ///
    /// Returns true when there have been no appends since the last snapshot,
    /// useful for early-exit optimizations.
    pub fn is_empty(&self) -> bool {
        self.messages.is_empty()
    }

    /// Returns a slice reference to all messages in the delta.
    ///
    /// Provides direct access to the underlying message array for bulk
    /// operations or index-based access.
    pub fn messages(&self) -> &[Message] {
        &self.messages
    }
}

impl IntoIterator for DeltaView {
    type Item = Message;
    type IntoIter = std::vec::IntoIter<Message>;

    /// Converts the DeltaView into an owning iterator over its messages.
    ///
    /// Consumes the DeltaView and returns an iterator that yields owned Message
    /// instances. Useful when you need to move messages out of the delta.
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
    /// Creates a new empty delta store with no session tracking.
    ///
    /// Initializes the internal HashMap wrapped in a RwLock for thread-safe
    /// concurrent access from multiple readers with exclusive writer access.
    pub fn new() -> Self {
        Self {
            deltas: RwLock::new(HashMap::new()),
        }
    }

    /// Initializes delta tracking for a session with an optional cursor position.
    ///
    /// Sets up the session's delta state with the snapshot cursor pointing to
    /// the last known message ID (or None for new sessions). Called during
    /// recovery to establish the baseline for tracking new messages.
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

    /// Appends a message to a session's delta after SQLite commit.
    ///
    /// Adds the message to the session's in-memory delta buffer. If the session
    /// doesn't exist in the store, creates a new entry. This must be called
    /// only after the message has been durably committed to SQLite.
    pub fn append(&self, session: &SessionId, message: Message) {
        let mut deltas = self.deltas.write().expect("lock poisoned");
        let delta = deltas.entry(session.clone()).or_insert_with(|| SessionDelta {
            snapshot_cursor: None,
            messages: Vec::new(),
        });
        delta.messages.push(message);
    }

    /// Retrieves a cloned delta view for the specified session.
    ///
    /// Returns a DeltaView containing all messages appended since the last
    /// snapshot. Returns an empty DeltaView if the session is not being tracked.
    /// The returned view is a snapshot that won't reflect subsequent appends.
    pub fn get(&self, session: &SessionId) -> DeltaView {
        let deltas = self.deltas.read().expect("lock poisoned");
        deltas
            .get(session)
            .map(|d| DeltaView::new(d.messages.clone()))
            .unwrap_or_else(DeltaView::empty)
    }

    /// Clears accumulated messages after a snapshot refresh.
    ///
    /// Updates the snapshot cursor to point to the last message (if any) and
    /// empties the message buffer. Called when refreshing snapshots to reset
    /// the delta tracking baseline to the current state.
    pub fn clear(&self, session: &SessionId) {
        let mut deltas = self.deltas.write().expect("lock poisoned");
        if let Some(delta) = deltas.get_mut(session) {
            // Update the cursor to the last message
            if let Some(last) = delta.messages.last() {
                delta.snapshot_cursor = Some(last.id.clone());
            }
            delta.messages.clear();
        }
    }

    /// Completely removes a session from delta tracking.
    ///
    /// Deletes all delta state for the session including the cursor and message
    /// buffer. Called when a session is deleted or closed permanently.
    pub fn remove(&self, session: &SessionId) {
        let mut deltas = self.deltas.write().expect("lock poisoned");
        deltas.remove(session);
    }
}

impl Default for DeltaStore {
    /// Returns a new empty DeltaStore as the default value.
    ///
    /// Delegates to `DeltaStore::new()` for consistent initialization.
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_message(id: &str, content: &str, seq: i64) -> Message {
        Message {
            id: MessageId::from_string(id),
            content: content.to_string(),
            sequence_number: seq,
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
        let messages = vec![make_message("1", "Hello", 1), make_message("2", "World", 2)];
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
        let session = SessionId::from_string("session-1");

        store.append(&session, make_message("1", "First", 1));
        store.append(&session, make_message("2", "Second", 2));

        let delta = store.get(&session);
        assert_eq!(delta.len(), 2);
        assert_eq!(delta.messages()[0].content, "First");
        assert_eq!(delta.messages()[1].content, "Second");
    }

    #[test]
    fn delta_store_clear() {
        let store = DeltaStore::new();
        let session = SessionId::from_string("session-1");

        store.append(&session, make_message("1", "Message", 1));
        assert_eq!(store.get(&session).len(), 1);

        store.clear(&session);
        assert!(store.get(&session).is_empty());
    }

    #[test]
    fn delta_store_remove() {
        let store = DeltaStore::new();
        let session = SessionId::from_string("session-1");

        store.init_session(session.clone(), None);
        store.append(&session, make_message("1", "Message", 1));
        assert_eq!(store.get(&session).len(), 1);

        store.remove(&session);
        assert!(store.get(&session).is_empty());
    }

    #[test]
    fn delta_store_multiple_sessions() {
        let store = DeltaStore::new();
        let session1 = SessionId::from_string("session-1");
        let session2 = SessionId::from_string("session-2");

        store.append(&session1, make_message("1", "Session 1", 1));
        store.append(&session2, make_message("2", "Session 2", 1));

        assert_eq!(store.get(&session1).len(), 1);
        assert_eq!(store.get(&session2).len(), 1);
        assert_eq!(store.get(&session1).messages()[0].content, "Session 1");
        assert_eq!(store.get(&session2).messages()[0].content, "Session 2");
    }
}
