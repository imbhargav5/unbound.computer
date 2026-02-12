//! IPC handler implementations.
//!
//! Each handler module contains thin handlers that compose the appropriate
//! store, store_stream, and machines modules.

pub mod claude;
pub mod git;
pub mod health;
pub mod message;
pub mod repository;
pub mod session;
pub mod system;
pub mod terminal;
