//! IPC layer for daemon-client communication.
//!
//! This crate provides:
//! - Unix domain socket server
//! - JSON-RPC-like protocol
//! - Request/response handling

mod error;
mod server;

pub use error::{IpcError, IpcResult};
pub use ipc_protocol_types::{error_codes, Event, EventType, Method, Request, Response};
pub use server::{IpcClient, IpcServer, StreamingSubscription, SubscriptionManager};
