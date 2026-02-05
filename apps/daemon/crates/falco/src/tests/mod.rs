//! Integration tests for the Falco courier.
//!
//! Test organization follows the Falco Integration Test Cases:
//!
//! - `harness.rs`      - Test harness with mock consumer and mock Redis
//! - `transport.rs`    - I. Transport Setup (Rules 1-4)
//! - `forwarding.rs`   - II. Forwarding Behavior (Rules 5-8)
//! - `ack.rs`          - III. ACK on Consumer Approval (Rules 9-12)
//!                     - IV. No ACK on Consumer Rejection (Rules 13-16)
//! - `backpressure.rs` - V. Blocking & Backpressure (Rules 17-20)
//! - `timeout.rs`      - VI. Timeout (Escape Hatch) (Rules 21-24)
//!                     - VII. Late Consumer Response (Rules 25-28)
//! - `ordering.rs`     - VIII. Ordering Guarantees (Rules 29-32)
//! - `crash_safety.rs` - IX. Crash Safety (In-Flight) (Rules 33-36)
//! - `transport_failure.rs` - X. Transport Failure Handling (Rules 37-40)
//! - `content.rs`      - XI. Content Agnosticism (Rules 41-44)
//! - `invariants.rs`   - XII. Hard Integration Invariants (Rules 45-48)

mod ack;
mod backpressure;
mod content;
mod crash_safety;
mod forwarding;
pub(crate) mod harness;
mod invariants;
mod ordering;
mod timeout;
mod transport;
mod transport_failure;

// Re-exports for external test usage if needed
#[allow(unused_imports)]
pub use harness::{MockConsumer, MockRedis, TestHarness};
