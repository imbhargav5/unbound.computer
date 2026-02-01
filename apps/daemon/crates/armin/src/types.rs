//! Core types for the Armin session engine.

use uuid::Uuid;

/// Unique identifier for a session (UUID string).
#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct SessionId(pub String);

impl SessionId {
    /// Creates a new random session ID.
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    /// Creates a session ID from an existing string.
    pub fn from_string(s: impl Into<String>) -> Self {
        Self(s.into())
    }

    /// Returns the session ID as a string slice.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for SessionId {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for SessionId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for SessionId {
    fn from(s: String) -> Self {
        Self(s)
    }
}

impl From<&str> for SessionId {
    fn from(s: &str) -> Self {
        Self(s.to_string())
    }
}

/// Unique identifier for a message (UUID string).
#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct MessageId(pub String);

impl MessageId {
    /// Creates a new random message ID.
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    /// Creates a message ID from an existing string.
    pub fn from_string(s: impl Into<String>) -> Self {
        Self(s.into())
    }

    /// Returns the message ID as a string slice.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for MessageId {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for MessageId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for MessageId {
    fn from(s: String) -> Self {
        Self(s)
    }
}

impl From<&str> for MessageId {
    fn from(s: &str) -> Self {
        Self(s.to_string())
    }
}

/// A message in a session.
///
/// Messages store raw content (typically JSON from Claude events).
/// No role interpretation is done - content is stored as-is.
#[derive(Clone, Debug, PartialEq)]
pub struct Message {
    pub id: MessageId,
    pub content: String,
    pub sequence_number: i64,
}

impl Message {
    /// Creates a new message for insertion.
    pub fn new(content: impl Into<String>) -> NewMessage {
        NewMessage {
            content: content.into(),
        }
    }
}

/// A message to be inserted.
///
/// The sequence number is assigned atomically by Armin during insertion.
/// Callers must NOT provide a sequence number - Armin owns all sequencing.
#[derive(Clone, Debug)]
pub struct NewMessage {
    pub content: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_id_equality() {
        let id1 = SessionId::from_string("test-session-1");
        let id2 = SessionId::from_string("test-session-1");
        let id3 = SessionId::from_string("test-session-2");
        assert_eq!(id1, id2);
        assert_ne!(id1, id3);
    }

    #[test]
    fn message_id_equality() {
        let id1 = MessageId::from_string("test-message-1");
        let id2 = MessageId::from_string("test-message-1");
        let id3 = MessageId::from_string("test-message-2");
        assert_eq!(id1, id2);
        assert_ne!(id1, id3);
    }

    #[test]
    fn session_id_new_is_unique() {
        let id1 = SessionId::new();
        let id2 = SessionId::new();
        assert_ne!(id1, id2);
    }

    #[test]
    fn message_id_new_is_unique() {
        let id1 = MessageId::new();
        let id2 = MessageId::new();
        assert_ne!(id1, id2);
    }

    #[test]
    fn session_id_display() {
        let id = SessionId::from_string("my-session");
        assert_eq!(format!("{}", id), "my-session");
    }

    #[test]
    fn session_id_from_string() {
        let id: SessionId = "test".into();
        assert_eq!(id.as_str(), "test");
    }
}
