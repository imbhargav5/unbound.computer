//! Outbox pattern implementation for reliable event delivery.
//!
//! This crate provides:
//! - OutboxManager: Actor-based manager for per-session outbox queues
//! - OutboxQueue: In-memory queue backed by SQLite for crash recovery
//! - PipelineSender: HTTP sender with retry and exponential backoff

mod error;
mod manager;
mod queue;
mod sender;

pub use error::{OutboxError, OutboxResult};
pub use manager::{OutboxManager, QueueStatus};
pub use queue::{EventBatch, OutboxQueue, MAX_BATCH_SIZE, MAX_IN_FLIGHT_BATCHES};
pub use sender::{PipelineSender, SenderConfig};
