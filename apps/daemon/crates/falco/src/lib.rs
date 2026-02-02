//! Falco: Stateless, crash-safe courier for encrypted remote commands.
//!
//! Falco moves encrypted commands from Redis Streams to a local daemon.
//! It ACKs Redis only when explicitly permitted by the daemon or when
//! a timeout expires.
//!
//! # Core Invariants
//!
//! 1. **Content-Agnostic**: Falco never inspects or modifies encrypted payloads
//! 2. **ACK-Gated**: Redis is ACKed only on daemon instruction or timeout
//! 3. **One In-Flight**: Only one command processed at a time (COUNT=1)
//! 4. **Crash-Safe**: Any crash results in automatic Redis redelivery
//!
//! # Architecture
//!
//! ```text
//! Redis Stream -> Falco -> Daemon
//!     ^                      |
//!     |______ XACK <________|
//! ```

pub mod config;
pub mod courier;
pub mod daemon_client;
pub mod error;
pub mod protocol;
pub mod redis_consumer;

#[cfg(test)]
mod tests;

pub use config::FalcoConfig;
pub use courier::Courier;
pub use daemon_client::DaemonClient;
pub use error::{FalcoError, FalcoResult};
pub use protocol::{CommandFrame, DaemonDecisionFrame, Decision};
pub use redis_consumer::{RedisConsumer, StreamMessage};
