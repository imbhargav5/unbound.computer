//! Armin adapter for daemon integration.
//!
//! This module bridges Armin's side-effects to the daemon's IPC subscription system.

use armin::{Armin, SideEffect, SideEffectSink};
use daemon_ipc::{Event, EventType, SubscriptionManager};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;
use tracing::{debug, info};

/// A side-effect sink that bridges Armin events to daemon subscriptions.
///
/// This sink receives side-effects from Armin (SessionCreated, MessageAppended, SessionClosed)
/// and broadcasts them to daemon IPC clients via the SubscriptionManager.
pub struct DaemonSideEffectSink {
    /// The subscription manager to broadcast events to.
    subscriptions: SubscriptionManager,
    /// Global sequence counter for events.
    sequence: AtomicI64,
}

impl DaemonSideEffectSink {
    /// Creates a new daemon side-effect sink.
    pub fn new(subscriptions: SubscriptionManager) -> Self {
        Self {
            subscriptions,
            sequence: AtomicI64::new(0),
        }
    }

    /// Gets the next sequence number for events.
    fn next_sequence(&self) -> i64 {
        self.sequence.fetch_add(1, Ordering::SeqCst)
    }
}

impl std::fmt::Debug for DaemonSideEffectSink {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DaemonSideEffectSink").finish_non_exhaustive()
    }
}

impl SideEffectSink for DaemonSideEffectSink {
    fn emit(&self, effect: SideEffect) {
        match effect {
            SideEffect::SessionCreated { session_id } => {
                debug!(session_id = %session_id, "Armin session created");
                let seq = self.next_sequence();
                self.subscriptions.broadcast_global(Event::new(
                    EventType::SessionCreated,
                    session_id.as_str(),
                    serde_json::json!({ "session_id": session_id.as_str() }),
                    seq,
                ));
            }

            SideEffect::MessageAppended {
                session_id,
                message_id,
            } => {
                debug!(
                    session_id = %session_id,
                    message_id = %message_id,
                    "Armin message appended"
                );
                // Message events are typically streamed via shared memory (daemon-stream)
                // rather than socket-based broadcasts for better performance.
                // This side effect can be used for other purposes like triggering sync.
            }

            SideEffect::SessionClosed { session_id } => {
                debug!(session_id = %session_id, "Armin session closed");
                let seq = self.next_sequence();
                self.subscriptions.broadcast_global(Event::new(
                    EventType::SessionDeleted,
                    session_id.as_str(),
                    serde_json::json!({ "session_id": session_id.as_str() }),
                    seq,
                ));
            }
        }
    }
}

/// The Armin engine configured for daemon use.
pub type DaemonArmin = Armin<DaemonSideEffectSink>;

/// Creates a new Armin engine for the daemon.
///
/// # Arguments
///
/// * `db_path` - Path to the Armin SQLite database file
/// * `subscriptions` - The daemon's subscription manager for broadcasting events
///
/// # Returns
///
/// The Armin engine wrapped in an Arc for shared access.
pub fn create_daemon_armin(
    db_path: &std::path::Path,
    subscriptions: SubscriptionManager,
) -> Result<Arc<DaemonArmin>, armin::ArminError> {
    let sink = DaemonSideEffectSink::new(subscriptions);
    let armin = Armin::open(db_path, sink)?;

    info!(path = %db_path.display(), "Armin session engine initialized");

    Ok(Arc::new(armin))
}

/// Creates an in-memory Armin engine for testing.
#[allow(dead_code)]
pub fn create_test_armin(
    subscriptions: SubscriptionManager,
) -> Result<Arc<DaemonArmin>, armin::ArminError> {
    let sink = DaemonSideEffectSink::new(subscriptions);
    let armin = Armin::in_memory(sink)?;

    Ok(Arc::new(armin))
}

#[cfg(test)]
mod tests {
    // Tests removed - the SessionIdMapper is no longer needed since Armin
    // now uses UUIDs directly via armin::SessionId
}
