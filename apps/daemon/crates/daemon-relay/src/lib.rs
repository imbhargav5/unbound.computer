//! WebSocket relay client for the Unbound daemon.
//!
//! This crate provides:
//! - WebSocket connection to the relay server
//! - Automatic reconnection with exponential backoff
//! - Session management (join/leave)
//! - Heartbeat for connection keepalive

mod client;
mod error;
mod messages;

pub use client::{RelayClient, RelayConfig, RelayEvent};
pub use error::{RelayError, RelayResult};
pub use messages::{RelayMessage, RelayMessageType};
