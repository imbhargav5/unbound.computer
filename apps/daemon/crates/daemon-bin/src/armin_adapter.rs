//! Armin adapter for daemon integration.
//!
//! This module bridges Armin's side-effects to the daemon's IPC subscription system.

use crate::observability::{current_trace_context, spawn_in_current_span};
use agent_session_sqlite_persist_core::{Armin, SideEffect, SideEffectSink};
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
        f.debug_struct("DaemonSideEffectSink")
            .finish_non_exhaustive()
    }
}

impl SideEffectSink for DaemonSideEffectSink {
    fn emit(&self, effect: SideEffect) {
        let trace_context = current_trace_context();
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
                let mut event = Event::new(
                    EventType::SessionCreated,
                    session_id.as_str(),
                    serde_json::json!({ "session_id": session_id.as_str() }),
                    seq,
                );
                if let Some(trace_context) = trace_context.clone() {
                    event = event.with_context(trace_context);
                }
                self.subscriptions.broadcast_global(event);
            }

            SideEffect::SessionClosed { session_id } => {
                debug!(session_id = %session_id, "Armin session closed");
                let seq = self.next_sequence();
                let mut event = Event::new(
                    EventType::SessionDeleted,
                    session_id.as_str(),
                    serde_json::json!({ "session_id": session_id.as_str() }),
                    seq,
                );
                if let Some(trace_context) = trace_context.clone() {
                    event = event.with_context(trace_context);
                }
                self.subscriptions.broadcast_global(event);
            }

            SideEffect::SessionDeleted { session_id } => {
                debug!(session_id = %session_id, "Armin session deleted");
                let seq = self.next_sequence();
                let mut event = Event::new(
                    EventType::SessionDeleted,
                    session_id.as_str(),
                    serde_json::json!({ "session_id": session_id.as_str() }),
                    seq,
                );
                if let Some(trace_context) = trace_context.clone() {
                    event = event.with_context(trace_context);
                }
                self.subscriptions.broadcast_global(event);
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
                let mut event = Event::new(
                    EventType::Message,
                    session_id.as_str(),
                    serde_json::json!({
                        "session_id": session_id.as_str(),
                        "message_id": message_id.as_str(),
                    }),
                    seq,
                );
                if let Some(trace_context) = trace_context.clone() {
                    event = event.with_context(trace_context);
                }
                let subscriptions = self.subscriptions.clone();
                let session_id_str = session_id.as_str().to_string();
                // Spawn async task since broadcast_or_create is async
                spawn_in_current_span(async move {
                    subscriptions
                        .broadcast_or_create(&session_id_str, event)
                        .await;
                });
            }

            SideEffect::RuntimeStatusUpdated {
                session_id,
                runtime_status,
            } => {
                debug!(
                    session_id = %session_id,
                    status = %runtime_status.coding_session.status.as_str(),
                    "Armin runtime status updated"
                );
                // Broadcast status change so clients know when Claude starts/stops
                let seq = self.next_sequence();
                let mut event = Event::new(
                    EventType::StatusChange,
                    session_id.as_str(),
                    serde_json::json!({
                        "session_id": session_id.as_str(),
                        "status": runtime_status.coding_session.status.as_str(),
                        "error_message": runtime_status.coding_session.error_message,
                        "runtime_status": runtime_status,
                    }),
                    seq,
                );
                if let Some(trace_context) = trace_context.clone() {
                    event = event.with_context(trace_context);
                }
                let subscriptions = self.subscriptions.clone();
                let session_id_str = session_id.as_str().to_string();
                spawn_in_current_span(async move {
                    subscriptions
                        .broadcast_or_create(&session_id_str, event)
                        .await;
                });
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
) -> Result<Arc<DaemonArmin>, agent_session_sqlite_persist_core::ArminError> {
    let sink = DaemonSideEffectSink::new(subscriptions);
    let armin = Armin::open(db_path, sink)?;

    info!(path = %db_path.display(), "Armin session engine initialized");

    Ok(Arc::new(armin))
}

/// Creates an in-memory Armin engine for testing.
#[allow(dead_code)]
pub fn create_test_armin(
    subscriptions: SubscriptionManager,
) -> Result<Arc<DaemonArmin>, agent_session_sqlite_persist_core::ArminError> {
    let sink = DaemonSideEffectSink::new(subscriptions);
    let armin = Armin::in_memory(sink)?;

    Ok(Arc::new(armin))
}

#[cfg(test)]
mod tests {
    // Tests removed - the SessionIdMapper is no longer needed since Armin
    // now uses UUIDs directly via agent_session_sqlite_persist_core::SessionId
}
