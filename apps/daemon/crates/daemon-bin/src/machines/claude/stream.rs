//! Claude event handling - bridges Deku events to Armin and IPC.

use crate::app::DaemonState;
use armin::{AgentStatus, NewMessage, SessionId, SessionWriter};
use daemon_ipc::{Event, EventType};
use deku::{ClaudeEvent, ClaudeEventStream};
use std::sync::atomic::{AtomicI64, Ordering};
use tracing::{debug, info, warn};

/// Global sequence counter for streaming events.
static STREAM_SEQUENCE: AtomicI64 = AtomicI64::new(0);

/// Handle Claude events from a Deku event stream.
///
/// This handler bridges Deku's Claude events to Armin and IPC:
/// 1. Stores raw JSON as messages via Armin
/// 2. Updates Claude session ID when received
/// 3. Broadcasts events to IPC subscribers
/// 4. Manages agent status
pub async fn handle_claude_events(
    mut stream: ClaudeEventStream,
    session_id: String,
    state: DaemonState,
) {
    info!(
        session_id = %session_id,
        "Starting to handle Claude events"
    );

    let armin_session_id = SessionId::from_string(&session_id);
    let mut event_count = 0;

    // Set agent status to running via Armin
    state
        .armin
        .update_agent_status(&armin_session_id, AgentStatus::Running);
    info!("Agent status set to RUNNING");

    // Process events from the stream
    while let Some(event) = stream.next().await {
        match &event {
            ClaudeEvent::Json { event_type, raw, .. } => {
                event_count += 1;

                // Store raw JSON via Armin
                let _message = state.armin.append(
                    &armin_session_id,
                    NewMessage {
                        content: raw.clone(),
                    },
                );

                // Broadcast to streaming subscribers
                broadcast_event(&state, &session_id, raw);

                debug!(event_num = event_count, event_type = %event_type, "event");
            }

            ClaudeEvent::SystemWithSessionId { claude_session_id, raw } => {
                event_count += 1;

                // Store raw JSON via Armin
                let _message = state.armin.append(
                    &armin_session_id,
                    NewMessage {
                        content: raw.clone(),
                    },
                );

                // Update claude_session_id via Armin
                state.armin.update_session_claude_id(&armin_session_id, claude_session_id);

                // Broadcast to streaming subscribers
                broadcast_event(&state, &session_id, raw);

                info!(
                    event_num = event_count,
                    claude_session = %claude_session_id,
                    "system event - Claude session ID"
                );
            }

            ClaudeEvent::Result { is_error, raw } => {
                event_count += 1;

                // Store raw JSON via Armin
                let _message = state.armin.append(
                    &armin_session_id,
                    NewMessage {
                        content: raw.clone(),
                    },
                );

                // Broadcast to streaming subscribers
                broadcast_event(&state, &session_id, raw);

                if *is_error {
                    warn!(event_num = event_count, "result event (error)");
                } else {
                    info!(event_num = event_count, "result event (success)");
                }

                // Update agent status to idle
                state.armin.update_agent_status(&armin_session_id, AgentStatus::Idle);
            }

            ClaudeEvent::Stderr { line } => {
                warn!(stderr = %line, "Claude stderr");
            }

            ClaudeEvent::Finished { success, exit_code } => {
                if *success {
                    info!(exit_code = ?exit_code, "Claude process finished successfully");
                } else {
                    warn!(exit_code = ?exit_code, "Claude process exited with non-zero status");
                }
            }

            ClaudeEvent::Stopped => {
                info!("Claude process was stopped");
            }
        }

        // Break on terminal events
        if event.is_terminal() {
            break;
        }
    }

    info!(event_count = event_count, "Processed events total");

    // Update agent status to idle via Armin
    state
        .armin
        .update_agent_status(&armin_session_id, AgentStatus::Idle);
    info!("Agent status set to IDLE");

    // Remove from running processes
    {
        let mut processes = state.claude_processes.lock().unwrap();
        processes.remove(&session_id);
        info!(session_id = %session_id, "Cleaned up Claude process");
    }
}

/// Broadcast a raw JSON event to IPC subscribers.
fn broadcast_event(state: &DaemonState, session_id: &str, raw_json: &str) {
    let seq = STREAM_SEQUENCE.fetch_add(1, Ordering::SeqCst);
    let event = Event::new(
        EventType::ClaudeEvent,
        session_id,
        serde_json::json!({ "raw_json": raw_json }),
        seq,
    );
    let subscriptions = state.subscriptions.clone();
    let session_id_for_broadcast = session_id.to_string();
    tokio::spawn(async move {
        subscriptions.broadcast_or_create(&session_id_for_broadcast, event).await;
    });
}
