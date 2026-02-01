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
    /// Creates a new subscription with the given receiver.
    fn new(session_id: SessionId, receiver: Receiver<Message>) -> Self {
        Self {
            receiver,
            _session_id: session_id,
        }
    }

    /// Receives the next message, blocking until one is available.
    ///
    /// Returns `None` if the subscription has been closed.
    pub fn recv(&self) -> Option<Message> {
        self.receiver.recv().ok()
    }

    /// Tries to receive the next message without blocking.
    ///
    /// Returns `None` if no message is available or the subscription has been closed.
    pub fn try_recv(&self) -> Option<Message> {
        self.receiver.try_recv().ok()
    }

    /// Returns an iterator over messages as they arrive.
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
    /// Creates a new empty live hub.
    pub fn new() -> Self {
        Self {
            subscribers: RwLock::new(HashMap::new()),
        }
    }

    /// Creates a subscription for a session.
    ///
    /// The subscription will receive all messages appended to the session
    /// after the subscription is created.
    pub fn subscribe(&self, session: SessionId) -> LiveSubscription {
        let (sender, receiver) = mpsc::channel();

        let mut subscribers = self.subscribers.write().expect("lock poisoned");
        subscribers
            .entry(session)
            .or_insert_with(Vec::new)
            .push(sender);

        LiveSubscription::new(session, receiver)
    }

    /// Notifies all subscribers of a session about a new message.
    ///
    /// This should be called after the message is committed to SQLite.
    /// Dead subscribers (those whose receivers have been dropped) are automatically removed.
    pub fn notify(&self, session: SessionId, message: Message) {
        let mut subscribers = self.subscribers.write().expect("lock poisoned");

        if let Some(senders) = subscribers.get_mut(&session) {
            // Send to all subscribers, removing dead ones
            senders.retain(|sender| sender.send(message.clone()).is_ok());
        }
    }

    /// Removes all subscribers for a session.
    ///
    /// This is typically called when a session is closed.
    pub fn close_session(&self, session: SessionId) {
        let mut subscribers = self.subscribers.write().expect("lock poisoned");
        subscribers.remove(&session);
    }

    /// Returns the number of active subscribers for a session.
    pub fn subscriber_count(&self, session: SessionId) -> usize {
        let subscribers = self.subscribers.read().expect("lock poisoned");
        subscribers.get(&session).map(|s| s.len()).unwrap_or(0)
    }
}

impl Default for LiveHub {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{MessageId, Role};

    fn make_message(id: u64, content: &str) -> Message {
        Message {
            id: MessageId(id),
            role: Role::User,
            content: content.to_string(),
        }
    }

    #[test]
    fn subscribe_and_receive() {
        let hub = LiveHub::new();
        let session = SessionId(1);

        let sub = hub.subscribe(session);
        assert_eq!(hub.subscriber_count(session), 1);

        hub.notify(session, make_message(1, "Hello"));

        let msg = sub.try_recv().unwrap();
        assert_eq!(msg.content, "Hello");
    }

    #[test]
    fn multiple_subscribers() {
        let hub = LiveHub::new();
        let session = SessionId(1);

        let sub1 = hub.subscribe(session);
        let sub2 = hub.subscribe(session);
        assert_eq!(hub.subscriber_count(session), 2);

        hub.notify(session, make_message(1, "Broadcast"));

        assert_eq!(sub1.try_recv().unwrap().content, "Broadcast");
        assert_eq!(sub2.try_recv().unwrap().content, "Broadcast");
    }

    #[test]
    fn dead_subscriber_cleanup() {
        let hub = LiveHub::new();
        let session = SessionId(1);

        // Create and drop a subscriber
        {
            let _sub = hub.subscribe(session);
            assert_eq!(hub.subscriber_count(session), 1);
        }

        // After sending a message, dead subscribers should be cleaned up
        hub.notify(session, make_message(1, "Test"));
        assert_eq!(hub.subscriber_count(session), 0);
    }

    #[test]
    fn close_session_removes_subscribers() {
        let hub = LiveHub::new();
        let session = SessionId(1);

        let _sub = hub.subscribe(session);
        assert_eq!(hub.subscriber_count(session), 1);

        hub.close_session(session);
        assert_eq!(hub.subscriber_count(session), 0);
    }

    #[test]
    fn multiple_sessions() {
        let hub = LiveHub::new();

        let sub1 = hub.subscribe(SessionId(1));
        let sub2 = hub.subscribe(SessionId(2));

        hub.notify(SessionId(1), make_message(1, "Session 1"));
        hub.notify(SessionId(2), make_message(2, "Session 2"));

        assert_eq!(sub1.try_recv().unwrap().content, "Session 1");
        assert_eq!(sub2.try_recv().unwrap().content, "Session 2");

        // Make sure they don't receive each other's messages
        assert!(sub1.try_recv().is_none());
        assert!(sub2.try_recv().is_none());
    }

    #[test]
    fn no_message_before_subscribe() {
        let hub = LiveHub::new();
        let session = SessionId(1);

        // Send message before subscription
        hub.notify(session, make_message(1, "Before"));

        // Subscribe after
        let sub = hub.subscribe(session);

        // Should not receive the message sent before subscription
        assert!(sub.try_recv().is_none());
    }
}
