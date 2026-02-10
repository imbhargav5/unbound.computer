//! # Armin
//!
//! A SQLite-backed session engine that commits facts, derives fast read views, and emits side-effects.
//!
//! ## Non-negotiable Principles
//!
//! - **SQLite is the only durable store** - Every write commits to SQLite first
//! - **Snapshots, deltas, live streams are derived** - Reads never cause side-effects
//! - **Side-effects reflect committed reality** - Emitted after SQLite commit
//! - **Recovery emits nothing** - Crash = rebuild from SQLite
//! - **Performance is achieved via derivation, not mutation**
//!
//! ## Architecture
//!
//! ```text
//! WRITE:
//!   SQLite → derived state → side-effect
//!
//! READ:
//!   snapshot + delta + live
//!
//! CRASH:
//!   SQLite → rebuild → continue
//! ```
//!
//! ## Example
//!
//! ```rust
//! use armin::{Armin, Message, NewMessage, SessionReader, SessionWriter};
//! use armin::side_effect::{RecordingSink, SideEffect};
//!
//! // Create an in-memory engine for testing
//! let sink = RecordingSink::new();
//! let engine = Armin::in_memory(sink).unwrap();
//!
//! // Create a session
//! let session_id = engine.create_session().unwrap();
//!
//! // Append messages
//! engine.append(&session_id, NewMessage {
//!     content: "Hello!".to_string(),
//! }).unwrap();
//!
//! // Read via delta
//! let delta = engine.delta(&session_id);
//! assert_eq!(delta.len(), 1);
//!
//! // Check side-effects were emitted
//! assert_eq!(engine.sink().len(), 2); // SessionCreated + MessageAppended
//! ```
//!
//! ## Crate Structure
//!
//! - [`armin`] - The Armin engine (brain)
//! - [`reader`] - Read-side traits
//! - [`writer`] - Write-side traits
//! - [`side_effect`] - Side-effect contracts
//! - [`types`] - Core types
//! - [`snapshot`] - Immutable snapshot views
//! - [`delta`] - Append-only deltas
//! - [`live`] - Live subscriptions

mod armin;
pub mod delta;
pub mod live;
pub mod reader;
pub mod side_effect;
pub mod snapshot;
mod sqlite;
pub mod types;
pub mod writer;

#[cfg(test)]
mod tests;

pub use crate::armin::Armin;
pub use reader::SessionReader;
pub use side_effect::{NullSink, RecordingSink, SideEffect, SideEffectSink};
pub use types::{
    AblySyncState, AgentStatus, Message, MessageId, NewMessage, NewRepository, NewSession,
    NewSessionSecret, PendingSupabaseMessage, PendingSyncMessage, Repository, RepositoryId,
    Session, SessionId, SessionPendingSync, SessionSecret, SessionState, SessionStatus,
    SessionUpdate, SupabaseMessageOutboxEntry, SupabaseSyncState, UserSetting,
};
pub use writer::SessionWriter;

/// Errors that can occur in Armin.
#[derive(Debug, thiserror::Error)]
pub enum ArminError {
    /// SQLite error.
    #[error("SQLite error: {0}")]
    Sqlite(#[from] rusqlite::Error),

    /// Session not found or closed.
    #[error("session not found or closed: {0}")]
    SessionNotFound(String),
}
