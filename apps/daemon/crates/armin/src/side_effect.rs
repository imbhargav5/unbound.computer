//! Side-effect contracts for the Armin session engine.
//!
//! Side-effects are emitted after facts are committed to SQLite.
//! They represent observable consequences of state changes.
//!
//! # Design Principles
//!
//! - Armin emits side-effects
//! - The sink decides what they mean
//! - Tests assert emission, not behavior
//! - Recovery emits nothing

use crate::types::{MessageId, SessionId};

/// A side-effect emitted by Armin after committing a fact.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SideEffect {
    /// A message was appended to a session.
    MessageAppended {
        session_id: SessionId,
        message_id: MessageId,
    },
    /// A session was closed.
    SessionClosed { session_id: SessionId },
    /// A new session was created.
    SessionCreated { session_id: SessionId },
}

/// A sink that receives side-effects from Armin.
///
/// Implementations decide how to handle side-effects (e.g., send notifications,
/// update external systems, log events).
pub trait SideEffectSink: Send + Sync {
    /// Emit a side-effect.
    ///
    /// This is called after the corresponding fact has been committed to SQLite.
    fn emit(&self, effect: SideEffect);
}

/// A no-op sink that discards all side-effects.
///
/// Useful for recovery or when side-effects are not needed.
#[derive(Debug, Default)]
pub struct NullSink;

impl SideEffectSink for NullSink {
    fn emit(&self, _effect: SideEffect) {
        // Intentionally empty - discard all side-effects
    }
}

/// A sink that records all side-effects for testing.
#[derive(Debug, Default)]
pub struct RecordingSink {
    effects: std::sync::Mutex<Vec<SideEffect>>,
}

impl RecordingSink {
    /// Creates a new recording sink.
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns all recorded side-effects.
    pub fn effects(&self) -> Vec<SideEffect> {
        self.effects.lock().expect("lock poisoned").clone()
    }

    /// Clears all recorded side-effects.
    pub fn clear(&self) {
        self.effects.lock().expect("lock poisoned").clear();
    }

    /// Returns the number of recorded side-effects.
    pub fn len(&self) -> usize {
        self.effects.lock().expect("lock poisoned").len()
    }

    /// Returns true if no side-effects have been recorded.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

impl SideEffectSink for RecordingSink {
    fn emit(&self, effect: SideEffect) {
        self.effects.lock().expect("lock poisoned").push(effect);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recording_sink_records_effects() {
        let sink = RecordingSink::new();
        assert!(sink.is_empty());

        let session_id = SessionId::from_string("session-1");
        let message_id = MessageId::from_string("message-1");

        sink.emit(SideEffect::SessionCreated {
            session_id: session_id.clone(),
        });
        sink.emit(SideEffect::MessageAppended {
            session_id: session_id.clone(),
            message_id: message_id.clone(),
        });

        assert_eq!(sink.len(), 2);
        let effects = sink.effects();
        assert_eq!(
            effects[0],
            SideEffect::SessionCreated {
                session_id: session_id.clone()
            }
        );
        assert_eq!(
            effects[1],
            SideEffect::MessageAppended {
                session_id: session_id.clone(),
                message_id: message_id.clone()
            }
        );
    }

    #[test]
    fn recording_sink_clear() {
        let sink = RecordingSink::new();
        sink.emit(SideEffect::SessionCreated {
            session_id: SessionId::from_string("session-1"),
        });
        assert!(!sink.is_empty());

        sink.clear();
        assert!(sink.is_empty());
    }

    #[test]
    fn null_sink_discards_effects() {
        let sink = NullSink;
        // Should not panic
        sink.emit(SideEffect::SessionCreated {
            session_id: SessionId::from_string("session-1"),
        });
    }
}
