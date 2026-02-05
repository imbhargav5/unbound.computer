//! SQLite database layer for the Unbound daemon.
//!
//! This crate provides:
//! - Async SQLite executor with dedicated thread
//! - Database migrations
//! - Model types for all tables
//! - ChaCha20-Poly1305 encryption for session secrets
//! - Query helpers for CRUD operations
//!
//! # Architecture
//!
//! The `AsyncDatabase` uses a single dedicated thread for all SQLite operations.
//! Queries are sent through a channel and executed in FIFO order.
//!
//! ```ignore
//! let db = AsyncDatabase::open(path).await?;
//! let repos = db.call(|conn| queries::list_repositories(conn)).await?;
//! ```
//!
//! **Important**: Only SQL operations should run inside `db.call()`.
//! Crypto, mutexes, and heavy computation must happen outside.
//!
//! # Message Storage
//!
//! Messages are stored as plain text in SQLite. Encryption is only used for
//! Supabase sync (handled separately, not in this crate).

mod db;
mod encryption;
mod error;
mod executor;
mod migrations;
mod models;
pub mod queries;

pub use db::Database;
// Encryption is still used for session secrets (encrypted with device key)
pub use encryption::{decrypt_content, encrypt_content, generate_nonce};
pub use error::{DatabaseError, DatabaseResult};
pub use executor::AsyncDatabase;
pub use migrations::run_migrations;
pub use models::*;
