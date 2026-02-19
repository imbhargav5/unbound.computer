//! Claude event handling - bridges Deku events to Armin and IPC.

use crate::app::DaemonState;
use armin::{CodingSessionStatus, NewMessage, SessionId, SessionWriter};
use claude_debug_logs::ClaudeDebugLogs;
use daemon_ipc::{Event, EventType};
use deku::{ClaudeEvent, ClaudeEventStream};
use std::sync::{
    atomic::{AtomicI64, Ordering},
    OnceLock,
};
use tracing::{debug, error, info, warn};

/// Global sequence counter for streaming events.
static STREAM_SEQUENCE: AtomicI64 = AtomicI64::new(0);
static CLAUDE_DEBUG_LOGS: OnceLock<ClaudeDebugLogs> = OnceLock::new();

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
    let mut last_status: Option<CodingSessionStatus> = None;
    let mut last_error_message: Option<String> = None;
    let mut terminal_status_written = false;

    // Start stream in running state.
    write_runtime_status_if_changed(
        &state,
        &armin_session_id,
        CodingSessionStatus::Running,
        None,
        "stream-start",
        &mut last_status,
        &mut last_error_message,
    );

    // Process events from the stream
    while let Some(event) = stream.next().await {
        match &event {
            ClaudeEvent::Json {
                event_type,
                raw,
                json,
            } => {
                event_count += 1;

                // Store raw JSON via Armin
                if let Err(e) = state.armin.append(
                    &armin_session_id,
                    NewMessage {
                        content: raw.clone(),
                    },
                ) {
                    warn!(error = %e, "Failed to store Claude JSON event");
                }

                // Broadcast to streaming subscribers
                broadcast_event(&state, &session_id, raw);

                if is_ask_user_question(json) {
                    write_runtime_status_if_changed(
                        &state,
                        &armin_session_id,
                        CodingSessionStatus::Waiting,
                        None,
                        "ask-user-question",
                        &mut last_status,
                        &mut last_error_message,
                    );
                } else {
                    write_runtime_status_if_changed(
                        &state,
                        &armin_session_id,
                        CodingSessionStatus::Running,
                        None,
                        "event-processing",
                        &mut last_status,
                        &mut last_error_message,
                    );
                }

                debug!(event_num = event_count, event_type = %event_type, "event");
            }

            ClaudeEvent::SystemWithSessionId {
                claude_session_id,
                raw,
            } => {
                event_count += 1;

                // Store raw JSON via Armin
                if let Err(e) = state.armin.append(
                    &armin_session_id,
                    NewMessage {
                        content: raw.clone(),
                    },
                ) {
                    warn!(error = %e, "Failed to store Claude system event");
                }

                // Update claude_session_id via Armin
                if let Err(e) = state
                    .armin
                    .update_session_claude_id(&armin_session_id, claude_session_id)
                {
                    warn!(error = %e, "Failed to update Claude session ID");
                }

                // Broadcast to streaming subscribers
                broadcast_event(&state, &session_id, raw);

                write_runtime_status_if_changed(
                    &state,
                    &armin_session_id,
                    CodingSessionStatus::Running,
                    None,
                    "system-event",
                    &mut last_status,
                    &mut last_error_message,
                );

                info!(
                    event_num = event_count,
                    claude_session = %claude_session_id,
                    "system event - Claude session ID"
                );
            }

            ClaudeEvent::Result { is_error, raw } => {
                event_count += 1;

                // Store raw JSON via Armin
                if let Err(e) = state.armin.append(
                    &armin_session_id,
                    NewMessage {
                        content: raw.clone(),
                    },
                ) {
                    warn!(error = %e, "Failed to store Claude result event");
                }

                // Broadcast to streaming subscribers
                broadcast_event(&state, &session_id, raw);

                if *is_error {
                    let error_message = extract_result_error_message(raw);
                    warn!(event_num = event_count, "result event (error)");
                    write_runtime_status_if_changed(
                        &state,
                        &armin_session_id,
                        CodingSessionStatus::Error,
                        Some(error_message),
                        "result-error",
                        &mut last_status,
                        &mut last_error_message,
                    );
                } else {
                    info!(event_num = event_count, "result event (success)");
                    write_runtime_status_if_changed(
                        &state,
                        &armin_session_id,
                        CodingSessionStatus::Idle,
                        None,
                        "result-success",
                        &mut last_status,
                        &mut last_error_message,
                    );
                }
                terminal_status_written = true;
            }

            ClaudeEvent::Stderr { line } => {
                warn!(stderr = %line, "Claude stderr");
            }

            ClaudeEvent::Finished { success, exit_code } => {
                if *success {
                    info!(exit_code = ?exit_code, "Claude process finished successfully");
                    if !terminal_status_written {
                        write_runtime_status_if_changed(
                            &state,
                            &armin_session_id,
                            CodingSessionStatus::Idle,
                            None,
                            "process-finished-success",
                            &mut last_status,
                            &mut last_error_message,
                        );
                        terminal_status_written = true;
                    }
                } else {
                    warn!(exit_code = ?exit_code, "Claude process exited with non-zero status");
                    if !terminal_status_written {
                        let error_message = match exit_code {
                            Some(code) => {
                                format!("Claude process exited with non-zero status ({code})")
                            }
                            None => "Claude process exited with non-zero status".to_string(),
                        };
                        write_runtime_status_if_changed(
                            &state,
                            &armin_session_id,
                            CodingSessionStatus::Error,
                            Some(error_message),
                            "process-finished-error",
                            &mut last_status,
                            &mut last_error_message,
                        );
                        terminal_status_written = true;
                    }
                }
            }

            ClaudeEvent::Stopped => {
                info!("Claude process was stopped");
                write_runtime_status_if_changed(
                    &state,
                    &armin_session_id,
                    CodingSessionStatus::NotAvailable,
                    None,
                    "process-stopped",
                    &mut last_status,
                    &mut last_error_message,
                );
                terminal_status_written = true;
            }
        }

        // Break on terminal events
        if event.is_terminal() {
            break;
        }
    }

    info!(event_count = event_count, "Processed events total");

    if !terminal_status_written {
        write_runtime_status_if_changed(
            &state,
            &armin_session_id,
            CodingSessionStatus::NotAvailable,
            None,
            "stream-cleanup",
            &mut last_status,
            &mut last_error_message,
        );
    }

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
    let claude_debug_logs = get_claude_debug_logs();
    if claude_debug_logs.is_enabled() {
        let claude_type = ClaudeDebugLogs::extract_claude_type(raw_json);
        info!(
            target: "unbound.claude.raw",
            event_code = "daemon.claude.raw",
            obs_prefix = "claude.raw",
            session_id = %session_id,
            sequence = seq,
            claude_type = %claude_type,
            raw_json = raw_json,
            "Claude raw event generated"
        );

        if let Err(e) = claude_debug_logs.record_raw_event(session_id, seq, raw_json) {
            warn!(
                session_id = %session_id,
                sequence = seq,
                base_dir = ?claude_debug_logs.base_dir(),
                error = %e,
                "Failed to append Claude debug log entry"
            );
        }
    }

    let event = Event::new(
        EventType::ClaudeEvent,
        session_id,
        serde_json::json!({ "raw_json": raw_json }),
        seq,
    );
    let subscriptions = state.subscriptions.clone();
    let session_id_for_broadcast = session_id.to_string();
    tokio::spawn(async move {
        subscriptions
            .broadcast_or_create(&session_id_for_broadcast, event)
            .await;
    });
}

fn get_claude_debug_logs() -> &'static ClaudeDebugLogs {
    CLAUDE_DEBUG_LOGS.get_or_init(ClaudeDebugLogs::from_env)
}

fn write_runtime_status_if_changed(
    state: &DaemonState,
    session_id: &SessionId,
    status: CodingSessionStatus,
    error_message: Option<String>,
    reason: &str,
    last_status: &mut Option<CodingSessionStatus>,
    last_error_message: &mut Option<String>,
) {
    if *last_status == Some(status) && *last_error_message == error_message {
        return;
    }

    let device_id = {
        let guard = state.device_id.lock().unwrap();
        guard.clone()
    };

    let Some(device_id) = device_id else {
        error!(
            session_id = %session_id,
            status = status.as_str(),
            reason,
            "Skipping runtime status write: local device_id unavailable"
        );
        return;
    };

    match state
        .armin
        .update_runtime_status(session_id, &device_id, status, error_message.clone())
    {
        Ok(()) => {
            *last_status = Some(status);
            *last_error_message = error_message;
        }
        Err(e) => {
            warn!(
                session_id = %session_id,
                status = status.as_str(),
                reason,
                error = %e,
                "Failed to write runtime status"
            );
        }
    }
}

fn is_ask_user_question(json: &serde_json::Value) -> bool {
    json.get("message")
        .and_then(|message| message.get("content"))
        .and_then(|content| content.as_array())
        .map(|blocks| {
            blocks.iter().any(|block| {
                block.get("type").and_then(|v| v.as_str()) == Some("tool_use")
                    && block.get("name").and_then(|v| v.as_str()) == Some("AskUserQuestion")
            })
        })
        .unwrap_or(false)
}

fn extract_result_error_message(raw_json: &str) -> String {
    let Ok(json) = serde_json::from_str::<serde_json::Value>(raw_json) else {
        return "Claude reported an error result".to_string();
    };

    if let Some(content) = json.get("content").and_then(|v| v.as_str()) {
        let trimmed = content.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }

    if let Some(text) = json
        .pointer("/result/content/0/text")
        .and_then(|v| v.as_str())
    {
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }

    "Claude reported an error result".to_string()
}

#[cfg(test)]
mod tests {
    use super::{extract_result_error_message, is_ask_user_question};

    #[test]
    fn ask_user_question_detected_from_tool_use_block() {
        let json = serde_json::json!({
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "AskUserQuestion",
                        "input": { "question": "Continue?" }
                    }
                ]
            }
        });

        assert!(is_ask_user_question(&json));
    }

    #[test]
    fn ask_user_question_not_detected_for_other_tools() {
        let json = serde_json::json!({
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Bash",
                        "input": { "command": "ls" }
                    }
                ]
            }
        });

        assert!(!is_ask_user_question(&json));
    }

    #[test]
    fn extract_error_message_from_content_field() {
        let raw = r#"{"type":"result","is_error":true,"content":"Operation failed"}"#;
        assert_eq!(extract_result_error_message(raw), "Operation failed");
    }

    #[test]
    fn extract_error_message_falls_back_to_default() {
        let raw = r#"{"type":"result","is_error":true}"#;
        assert_eq!(
            extract_result_error_message(raw),
            "Claude reported an error result"
        );
    }
}
