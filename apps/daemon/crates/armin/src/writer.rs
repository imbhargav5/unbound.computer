//! Write-side traits for the Armin session engine.
//!
//! Writes are where reality happens.
//!
//! # Design Principles
//!
//! - All writes commit to SQLite first
//! - Derived state is updated after commit
//! - Side-effects are emitted after derived state is updated
//! - If SQLite write fails, nothing else happens

use crate::types::{MessageId, NewMessage, SessionId};

/// A writer for session data.
///
/// All write operations follow the strict order:
/// 1. Commit fact to SQLite
/// 2. Update derived state
/// 3. Emit side-effect
pub trait SessionWriter {
    /// Creates a new session.
    ///
    /// Returns the ID of the newly created session.
    fn create_session(&self) -> SessionId;

    /// Appends a message to a session.
    ///
    /// Returns the ID of the newly created message.
    ///
    /// # Panics
    ///
    /// Panics if the session does not exist or is closed.
    fn append(&self, session: SessionId, message: NewMessage) -> MessageId;

    /// Closes a session.
    ///
    /// After closing, no more messages can be appended to the session.
    fn close(&self, session: SessionId);
}
