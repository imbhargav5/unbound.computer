//! Read-side traits for the Armin session engine.
//!
//! Reads are pure, derived, and fast.
//!
//! # Design Principles
//!
//! - Reads never hit SQLite directly (except on recovery)
//! - Reads never emit side-effects
//! - All read state is derived from SQLite on startup

use crate::delta::DeltaView;
use crate::live::LiveSubscription;
use crate::snapshot::SnapshotView;
use crate::types::SessionId;

/// A reader for session data.
///
/// Provides access to snapshots, deltas, and live subscriptions.
pub trait SessionReader {
    /// Returns a snapshot view of all sessions.
    fn snapshot(&self) -> SnapshotView;

    /// Returns a delta view for a specific session.
    ///
    /// The delta contains messages appended since the last snapshot.
    fn delta(&self, session: &SessionId) -> DeltaView;

    /// Subscribes to live updates for a specific session.
    ///
    /// Returns a subscription that yields new messages as they are appended.
    fn subscribe(&self, session: &SessionId) -> LiveSubscription;
}
