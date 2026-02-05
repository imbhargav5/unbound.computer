//! Live subscriptions for the Armin session engine.
//!
//! Live subscriptions provide real-time updates for session messages.
//!
//! # Design Principles
//!
//! - Subscriptions are notified after facts are committed
//! - Subscriptions are derived from committed state
//! - Recovery does not trigger live notifications

use std::collections::HashMap;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::RwLock;

use crate::types::{Message, SessionId};

/// A subscription to live updates for a session.
pub struct LiveSubscription {
    receiver: Receiver<Message>,
    _session_id: SessionId,
}

impl LiveSubscription {
    /// Creates a new subscription instance with the given MPSC receiver.
    ///
    /// Internal constructor used by LiveHub to wrap the receiver end of a
    /// channel. The session_id is stored for potential future use (debugging, filtering).
    fn new(session_id: SessionId, receiver: Receiver<Message>) -> Self {
        Self {
            receiver,
            _session_id: session_id,
        }
    }

    /// Blocks the current thread until a new message is available.
    ///
    /// Returns the next message when it arrives, or None if the subscription
    /// has been closed (all senders dropped or session closed). Useful for
    /// worker threads that process messages as they arrive.
    pub fn recv(&self) -> Option<Message> {
        self.receiver.recv().ok()
    }

    /// Attempts to receive a message without blocking the current thread.
    ///
    /// Returns Some(Message) if a message is immediately available, or None
    /// if the queue is empty or the subscription has been closed. Useful for
    /// polling in event loops or non-blocking contexts.
    pub fn try_recv(&self) -> Option<Message> {
        self.receiver.try_recv().ok()
    }

    /// Creates a blocking iterator that yields messages as they arrive.
    ///
    /// The iterator will block waiting for each message and terminate when
    /// the subscription is closed. Enables idiomatic for-loop consumption
    /// of the message stream.
    pub fn iter(&self) -> impl Iterator<Item = Message> + '_ {
        std::iter::from_fn(|| self.recv())
    }
}

/// A hub that manages live subscriptions for all sessions.
#[derive(Debug)]
pub struct LiveHub {
    /// Map of session ID to list of subscribers
    subscribers: RwLock<HashMap<SessionId, Vec<Sender<Message>>>>,
}

impl LiveHub {
    /// Creates a new empty hub with no active subscriptions.
    ///
    /// Initializes the subscriber map wrapped in a RwLock for thread-safe
    /// access from multiple concurrent sessions and notification sources.
    pub fn new() -> Self {
        Self {
            subscribers: RwLock::new(HashMap::new()),
        }
    }

    /// Creates a new subscription for receiving live updates on a session.
    ///
    /// Sets up an MPSC channel and registers the sender with the hub. The
    /// returned LiveSubscription receives all messages appended to the session
    /// after this call. Messages sent before subscription are not received.
    pub fn subscribe(&self, session: &SessionId) -> LiveSubscription {
        let (sender, receiver) = mpsc::channel();

        let mut subscribers = self.subscribers.write().expect("lock poisoned");
        subscribers
            .entry(session.clone())
            .or_insert_with(Vec::new)
            .push(sender);

        LiveSubscription::new(session.clone(), receiver)
    }

    /// Broadcasts a message to all subscribers of a session.
    ///
    /// Clones the message and sends it to each registered subscriber. Dead
    /// subscribers (where the receiver has been dropped) are automatically
    /// removed during this operation. Must be called after SQLite commit.
    pub fn notify(&self, session: &SessionId, message: Message) {
        let mut subscribers = self.subscribers.write().expect("lock poisoned");

        if let Some(senders) = subscribers.get_mut(session) {
            // Send to all subscribers, removing dead ones
            senders.retain(|sender| sender.send(message.clone()).is_ok());
        }
    }

    /// Removes all subscribers for a session and closes their channels.
    ///
    /// Called when a session is closed to clean up resources. All pending
    /// receives on subscriptions will return None after this call.
    pub fn close_session(&self, session: &SessionId) {
        let mut subscribers = self.subscribers.write().expect("lock poisoned");
        subscribers.remove(session);
    }

    /// Returns the count of currently registered subscribers for a session.
    ///
    /// Useful for debugging and testing. Note that this count may include
    /// dead subscribers that haven't been cleaned up by a notify() call yet.
    pub fn subscriber_count(&self, session: &SessionId) -> usize {
        let subscribers = self.subscribers.read().expect("lock poisoned");
        subscribers.get(session).map(|s| s.len()).unwrap_or(0)
    }
}

impl Default for LiveHub {
    /// Returns a new empty LiveHub as the default value.
    ///
    /// Delegates to `LiveHub::new()` for consistent initialization.
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::MessageId;

    fn make_message(id: &str, content: &str) -> Message {
        Message {
            id: MessageId::from_string(id),
            content: content.to_string(),
            sequence_number: 0,
        }
    }

    #[test]
    fn subscribe_and_receive() {
        let hub = LiveHub::new();
        let session = SessionId::from_string("session-1");

        let sub = hub.subscribe(&session);
        assert_eq!(hub.subscriber_count(&session), 1);

        hub.notify(&session, make_message("1", "Hello"));

        let msg = sub.try_recv().unwrap();
        assert_eq!(msg.content, "Hello");
    }

    #[test]
    fn multiple_subscribers() {
        let hub = LiveHub::new();
        let session = SessionId::from_string("session-1");

        let sub1 = hub.subscribe(&session);
        let sub2 = hub.subscribe(&session);
        assert_eq!(hub.subscriber_count(&session), 2);

        hub.notify(&session, make_message("1", "Broadcast"));

        assert_eq!(sub1.try_recv().unwrap().content, "Broadcast");
        assert_eq!(sub2.try_recv().unwrap().content, "Broadcast");
    }

    #[test]
    fn dead_subscriber_cleanup() {
        let hub = LiveHub::new();
        let session = SessionId::from_string("session-1");

        // Create and drop a subscriber
        {
            let _sub = hub.subscribe(&session);
            assert_eq!(hub.subscriber_count(&session), 1);
        }

        // After sending a message, dead subscribers should be cleaned up
        hub.notify(&session, make_message("1", "Test"));
        assert_eq!(hub.subscriber_count(&session), 0);
    }

    #[test]
    fn close_session_removes_subscribers() {
        let hub = LiveHub::new();
        let session = SessionId::from_string("session-1");

        let _sub = hub.subscribe(&session);
        assert_eq!(hub.subscriber_count(&session), 1);

        hub.close_session(&session);
        assert_eq!(hub.subscriber_count(&session), 0);
    }

    #[test]
    fn multiple_sessions() {
        let hub = LiveHub::new();
        let session1 = SessionId::from_string("session-1");
        let session2 = SessionId::from_string("session-2");

        let sub1 = hub.subscribe(&session1);
        let sub2 = hub.subscribe(&session2);

        hub.notify(&session1, make_message("1", "Session 1"));
        hub.notify(&session2, make_message("2", "Session 2"));

        assert_eq!(sub1.try_recv().unwrap().content, "Session 1");
        assert_eq!(sub2.try_recv().unwrap().content, "Session 2");

        // Make sure they don't receive each other's messages
        assert!(sub1.try_recv().is_none());
        assert!(sub2.try_recv().is_none());
    }

    #[test]
    fn no_message_before_subscribe() {
        let hub = LiveHub::new();
        let session = SessionId::from_string("session-1");

        // Send message before subscription
        hub.notify(&session, make_message("1", "Before"));

        // Subscribe after
        let sub = hub.subscribe(&session);

        // Should not receive the message sent before subscription
        assert!(sub.try_recv().is_none());
    }
}
