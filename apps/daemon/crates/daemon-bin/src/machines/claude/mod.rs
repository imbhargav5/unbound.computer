//! Claude CLI event handling.
//!
//! This module bridges Claude process events to the daemon's
//! Armin session engine and IPC system.

mod stream;

pub use stream::handle_claude_events;
