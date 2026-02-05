//! Armin adapter for daemon integration.
//!
//! This module bridges Armin's side-effects to the daemon's IPC subscription system.

use armin::{Armin, SideEffect, SideEffectSink};
use daemon_ipc::{Event, EventType, SubscriptionManager};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;
use toshinori::ToshinoriSink;
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

/// Composite sink that broadcasts to IPC and optionally syncs to Supabase.
pub struct DaemonCompositeSink {
    daemon_sink: DaemonSideEffectSink,
    toshinori: Option<Arc<ToshinoriSink>>,
}

impl DaemonCompositeSink {
    pub fn new(subscriptions: SubscriptionManager, toshinori: Option<Arc<ToshinoriSink>>) -> Self {
        Self {
            daemon_sink: DaemonSideEffectSink::new(subscriptions),
            toshinori,
        }
    }
}

impl SideEffectSink for DaemonCompositeSink {
    fn emit(&self, effect: SideEffect) {
        self.daemon_sink.emit(effect.clone());
        if let Some(toshinori) = &self.toshinori {
            toshinori.emit(effect);
        }
    }
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
            SideEffect::RepositoryCreated { repository_id } => {
                debug!(repository_id = %repository_id, "Armin repository created");
                // Repository events are not currently broadcast
            }

            SideEffect::RepositoryDeleted { repository_id } => {
                debug!(repository_id = %repository_id, "Armin repository deleted");
                // Repository events are not currently broadcast
            }

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

            SideEffect::SessionDeleted { session_id } => {
                debug!(session_id = %session_id, "Armin session deleted");
                let seq = self.next_sequence();
                self.subscriptions.broadcast_global(Event::new(
                    EventType::SessionDeleted,
                    session_id.as_str(),
                    serde_json::json!({ "session_id": session_id.as_str() }),
                    seq,
                ));
            }

            SideEffect::SessionUpdated { session_id } => {
                debug!(session_id = %session_id, "Armin session updated");
                // Session updates are not currently broadcast
            }

            SideEffect::MessageAppended {
                session_id,
                message_id,
                sequence_number: _,
                content: _,
            } => {
                debug!(
                    session_id = %session_id,
                    message_id = %message_id,
                    "Armin message appended"
                );
                // Broadcast to session subscribers so clients get notified
                let seq = self.next_sequence();
                let event = Event::new(
                    EventType::Message,
                    session_id.as_str(),
                    serde_json::json!({
                        "session_id": session_id.as_str(),
                        "message_id": message_id.as_str(),
                    }),
                    seq,
                );
                let subscriptions = self.subscriptions.clone();
                let session_id_str = session_id.as_str().to_string();
                // Spawn async task since broadcast_or_create is async
                tokio::spawn(async move {
                    subscriptions.broadcast_or_create(&session_id_str, event).await;
                });
            }

            SideEffect::AgentStatusChanged { session_id, status } => {
                debug!(
                    session_id = %session_id,
                    status = %status.as_str(),
                    "Armin agent status changed"
                );
                // Broadcast status change so clients know when Claude starts/stops
                let seq = self.next_sequence();
                let event = Event::new(
                    EventType::StatusChange,
                    session_id.as_str(),
                    serde_json::json!({
                        "session_id": session_id.as_str(),
                        "status": status.as_str(),
                    }),
                    seq,
                );
                let subscriptions = self.subscriptions.clone();
                let session_id_str = session_id.as_str().to_string();
                tokio::spawn(async move {
                    subscriptions.broadcast_or_create(&session_id_str, event).await;
                });
            }

            SideEffect::OutboxEventsSent { batch_id } => {
                debug!(batch_id = %batch_id, "Armin outbox events sent");
                // Outbox events are not currently broadcast
            }

            SideEffect::OutboxEventsAcked { batch_id } => {
                debug!(batch_id = %batch_id, "Armin outbox events acked");
                // Outbox events are not currently broadcast
            }
        }
    }
}

/// The Armin engine configured for daemon use.
pub type DaemonArmin = Armin<DaemonCompositeSink>;

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
    toshinori: Option<Arc<ToshinoriSink>>,
) -> Result<Arc<DaemonArmin>, armin::ArminError> {
    let sink = DaemonCompositeSink::new(subscriptions, toshinori);
    let armin = Armin::open(db_path, sink)?;

    info!(path = %db_path.display(), "Armin session engine initialized");

    Ok(Arc::new(armin))
}

/// Creates an in-memory Armin engine for testing.
#[allow(dead_code)]
pub fn create_test_armin(
    subscriptions: SubscriptionManager,
) -> Result<Arc<DaemonArmin>, armin::ArminError> {
    let sink = DaemonCompositeSink::new(subscriptions, None);
    let armin = Armin::in_memory(sink)?;

    Ok(Arc::new(armin))
}

#[cfg(test)]
mod tests {
    // Tests removed - the SessionIdMapper is no longer needed since Armin
    // now uses UUIDs directly via armin::SessionId
}
