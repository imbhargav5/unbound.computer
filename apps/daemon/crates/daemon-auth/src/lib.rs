//! Backward-compatible shim for the renamed auth crate.
//!
//! New code should depend on `auth-engine` directly.

pub use auth_engine::*;
