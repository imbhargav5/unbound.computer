//! Claude process output streaming and event handling.

use crate::app::DaemonState;
use armin::{AgentStatus, NewMessage, SessionId, SessionWriter};
use daemon_ipc::{Event, EventType};
use regex::Regex;
use std::sync::atomic::{AtomicI64, Ordering};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Child;
use tokio::sync::broadcast;
use tracing::{debug, error, info, warn};

/// Global sequence counter for streaming events.
static STREAM_SEQUENCE: AtomicI64 = AtomicI64::new(0);

/// Handle Claude process output, storing raw JSON as messages via Armin.
///
/// This handler:
/// 1. Validates each line is parseable JSON
/// 2. Extracts `type` field for logging
/// 3. Stores raw JSON as plain text via Armin
/// 4. Armin emits MessageAppended side-effects for client notifications
pub async fn handle_claude_process(
    mut child: Child,
    session_id: String,
    state: DaemonState,
    stop_tx: broadcast::Sender<()>,
) {
    info!(
        session_id = %session_id,
        "Starting to handle Claude process"
    );

    let mut stop_rx = stop_tx.subscribe();

    // ANSI escape code regex
    let ansi_regex = Regex::new(r"\x1B(?:\[[0-9;?]*[A-Za-z~]|\][^\x07]*\x07)").unwrap();

    // Set agent status to running via Armin
    let armin_session_id = SessionId::from_string(&session_id);
    state
        .armin
        .update_agent_status(&armin_session_id, AgentStatus::Running);
    info!("Agent status set to RUNNING");

    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => {
            error!("Failed to get stdout from Claude process");
            return;
        }
    };

    let stderr = child.stderr.take();

    let mut reader = BufReader::new(stdout).lines();
    let mut event_count = 0;

    info!("Starting to read Claude stdout...");

    loop {
        tokio::select! {
            // Check for stop signal
            _ = stop_rx.recv() => {
                info!("Stop signal received - killing process");
                let _ = child.kill().await;
                break;
            }

            // Read next line from stdout
            line_result = reader.next_line() => {
                match line_result {
                    Ok(Some(line)) => {
                        // Strip ANSI escape codes
                        let clean_line = ansi_regex.replace_all(&line, "").to_string();

                        // Skip empty lines
                        if clean_line.trim().is_empty() {
                            continue;
                        }

                        // Only process lines that look like JSON
                        if !clean_line.trim_start().starts_with('{') {
                            debug!(
                                line = %if clean_line.len() > 80 { &clean_line[..80] } else { &clean_line },
                                "Skipping non-JSON line"
                            );
                            continue;
                        }

                        // Try to parse as JSON
                        let json = match serde_json::from_str::<serde_json::Value>(&clean_line) {
                            Ok(j) => j,
                            Err(e) => {
                                warn!(error = %e, "Failed to parse JSON");
                                continue;
                            }
                        };

                        event_count += 1;
                        let event_type = json.get("type").and_then(|v| v.as_str()).unwrap_or("unknown");

                        // Store raw JSON via Armin (sequence number assigned atomically)
                        // This triggers MessageAppended side-effect for client notification
                        let _message = state.armin.append(
                            &armin_session_id,
                            NewMessage {
                                content: clean_line.clone(),
                            },
                        );

                        // Broadcast raw JSON to streaming subscribers for real-time display
                        let seq = STREAM_SEQUENCE.fetch_add(1, Ordering::SeqCst);
                        let event = Event::new(
                            EventType::ClaudeEvent,
                            &session_id,
                            serde_json::json!({ "raw_json": clean_line }),
                            seq,
                        );
                        let subscriptions = state.subscriptions.clone();
                        let session_id_for_broadcast = session_id.clone();
                        tokio::spawn(async move {
                            subscriptions.broadcast_or_create(&session_id_for_broadcast, event).await;
                        });

                        // Log the event
                        match event_type {
                            "system" => {
                                if let Some(new_session_id) = json.get("session_id").and_then(|v| v.as_str()) {
                                    // Update claude_session_id via Armin
                                    state.armin.update_session_claude_id(&armin_session_id, new_session_id);
                                    info!(
                                        event_num = event_count,
                                        claude_session = %new_session_id,
                                        "system event - Claude session ID"
                                    );
                                } else {
                                    let subtype = json.get("subtype").and_then(|v| v.as_str());
                                    info!(
                                        event_num = event_count,
                                        subtype = ?subtype,
                                        "system event"
                                    );
                                }
                            }
                            "assistant" => {
                                debug!(event_num = event_count, "assistant event");
                            }
                            "user" => {
                                debug!(event_num = event_count, "user event");
                            }
                            "result" => {
                                let is_error = json.get("is_error").and_then(|v| v.as_bool()).unwrap_or(false);
                                if is_error {
                                    warn!(event_num = event_count, "result event (error)");
                                } else {
                                    info!(event_num = event_count, "result event (success)");
                                }
                                // Update agent status to idle
                                state.armin.update_agent_status(&armin_session_id, AgentStatus::Idle);
                            }
                            _ => {
                                debug!(event_num = event_count, event_type = %event_type, "event");
                            }
                        }
                    }
                    Ok(None) => {
                        // EOF - process finished
                        info!("Claude stdout closed (EOF)");
                        break;
                    }
                    Err(e) => {
                        error!(error = %e, "Error reading Claude stdout");
                        break;
                    }
                }
            }
        }
    }

    info!(event_count = event_count, "Processed events total");

    // Read any remaining stderr
    if let Some(stderr) = stderr {
        let mut stderr_reader = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = stderr_reader.next_line().await {
            warn!(stderr = %line, "Claude stderr");
        }
    }

    // Wait for process to finish
    match child.wait().await {
        Ok(status) => {
            if status.success() {
                info!("Claude process finished successfully");
            } else {
                warn!(status = ?status, "Claude process exited with non-zero status");
            }
        }
        Err(e) => {
            error!(error = %e, "Error waiting for Claude process");
        }
    }

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
