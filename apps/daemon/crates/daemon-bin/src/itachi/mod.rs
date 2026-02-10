//! Itachi: inbound remote-command decision brain.
//!
//! Itachi owns remote command validation/routing and delegates transport
//! concerns to Nagato (ingress/ack publish) and Falco (egress publish).

pub mod channels;
pub mod contracts;
pub mod errors;
pub mod handler;
pub mod idempotency;
pub mod ports;
pub mod runtime;
