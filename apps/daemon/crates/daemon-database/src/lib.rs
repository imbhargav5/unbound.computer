//! SQLite database layer for the Unbound daemon.
//!
//! This crate provides:
//! - Async SQLite executor with dedicated thread (preferred)
//! - Legacy connection pool with WAL mode (deprecated)
//! - Database migrations
//! - Model types for all tables
//! - ChaCha20-Poly1305 encryption for message content
//! - Query helpers for CRUD operations
//!
//! # Architecture
//!
//! ## Async Executor (Recommended)
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
//! ## Legacy Pool (Deprecated)
//!
//! The `DatabasePool` uses r2d2 with multiple connections. This is being
//! phased out in favor of the async executor.

mod db;
mod encryption;
mod error;
mod executor;
mod migrations;
mod models;
mod pool;
pub mod queries;

pub use db::Database;
pub use encryption::{decrypt_content, encrypt_content, generate_nonce};
pub use error::{DatabaseError, DatabaseResult};
pub use executor::AsyncDatabase;
pub use migrations::run_migrations;
pub use models::*;
// Legacy exports - kept for backwards compatibility
pub use pool::{DatabasePool, PoolConfig, PoolState};
