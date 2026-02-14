//! Toshinori: Supabase sync sink for Armin side-effects.
//!
//! This crate provides a `SideEffectSink` implementation that syncs Armin's
//! committed facts to Supabase in real-time.
//!
//! # Architecture
//!
//! ```text
//! Armin (SQLite commit) → SideEffect → Toshinori → Supabase REST API
//! ```
//!
//! # Design Principles
//!
//! - **Non-blocking**: Side-effect handling is async and doesn't block Armin
//! - **Fire-and-forget**: Failed syncs are logged but don't fail the operation
//! - **Idempotent**: Uses upsert operations for safe retries
//! - **Minimal coupling**: Only depends on Armin's public types

mod ably_sync;
mod client;
mod error;
mod sink;

pub use ably_sync::{AblyArminAccess, AblyArminHandle, AblyRealtimeSyncer, AblySyncConfig};
pub use client::{MessageUpsert, SupabaseClient};
pub use error::{ToshinoriError, ToshinoriResult};
pub use sink::{
    MessageSyncRequest, MessageSyncer, RuntimeStatusSyncRequest, RuntimeStatusSyncer,
    SessionMetadata, SessionMetadataProvider, SyncContext, ToshinoriSink,
};
