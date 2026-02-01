//! Core types for the Armin session engine.

/// Unique identifier for a session.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub struct SessionId(pub u64);

/// Unique identifier for a message within a session.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub struct MessageId(pub u64);

/// A message in a session.
#[derive(Clone, Debug, PartialEq)]
pub struct Message {
    pub id: MessageId,
    pub role: Role,
    pub content: String,
}

impl Message {
    /// Creates a new message without an ID (for insertion).
    pub fn new(role: Role, content: impl Into<String>) -> NewMessage {
        NewMessage {
            role,
            content: content.into(),
        }
    }
}

/// A message to be inserted (without an ID yet).
#[derive(Clone, Debug)]
pub struct NewMessage {
    pub role: Role,
    pub content: String,
}

/// The role of a message sender.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Role {
    User,
    Assistant,
}

impl Role {
    /// Converts the role to its integer representation for storage.
    pub fn to_i32(self) -> i32 {
        match self {
            Role::User => 0,
            Role::Assistant => 1,
        }
    }

    /// Creates a role from its integer representation.
    pub fn from_i32(value: i32) -> Option<Self> {
        match value {
            0 => Some(Role::User),
            1 => Some(Role::Assistant),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn role_roundtrip() {
        assert_eq!(Role::from_i32(Role::User.to_i32()), Some(Role::User));
        assert_eq!(
            Role::from_i32(Role::Assistant.to_i32()),
            Some(Role::Assistant)
        );
        assert_eq!(Role::from_i32(99), None);
    }

    #[test]
    fn session_id_equality() {
        assert_eq!(SessionId(1), SessionId(1));
        assert_ne!(SessionId(1), SessionId(2));
    }

    #[test]
    fn message_id_equality() {
        assert_eq!(MessageId(1), MessageId(1));
        assert_ne!(MessageId(1), MessageId(2));
    }
}
