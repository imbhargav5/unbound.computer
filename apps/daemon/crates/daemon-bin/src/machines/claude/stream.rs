//! Claude process output streaming and event handling.

use crate::app::DaemonState;
use daemon_database::{queries, AgentStatus};
use daemon_stream::{EventType as StreamEventType, StreamProducer};
use regex::Regex;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Child;
use tokio::sync::broadcast;
use tracing::{debug, error, info, warn};

/// Handle Claude process output, storing raw JSON as messages in the database.
///
/// This simplified handler:
/// 1. Validates each line is parseable JSON
/// 2. Extracts `type` field to map to `role` column
/// 3. Stores raw JSON encrypted in messages table
/// 4. Streams events via shared memory for clients to consume
pub async fn handle_claude_process(
    mut child: Child,
    session_id: String,
    state: DaemonState,
    stop_tx: broadcast::Sender<()>,
) {
    info!(
        "\x1b[35m[PROCESS]\x1b[0m Starting to handle Claude process for session: {}",
        session_id
    );

    let mut stop_rx = stop_tx.subscribe();

    // ANSI escape code regex
    let ansi_regex = Regex::new(r"\x1B(?:\[[0-9;?]*[A-Za-z~]|\][^\x07]*\x07)").unwrap();

    // Create shared memory stream producer for event delivery
    let stream_producer: Option<Arc<StreamProducer>> = match StreamProducer::new(&session_id) {
        Ok(producer) => {
            let producer = Arc::new(producer);
            // Store in state for client discovery
            state
                .stream_producers
                .lock()
                .unwrap()
                .insert(session_id.clone(), producer.clone());
            info!(
                "\x1b[35m[PROCESS]\x1b[0m Created shared memory stream for session: {}",
                session_id
            );
            Some(producer)
        }
        Err(e) => {
            error!(
                "\x1b[31m[PROCESS]\x1b[0m Failed to create shared memory stream: {}. Clients will not receive events.",
                e
            );
            None
        }
    };

    // Get encryption key for storing messages (checks cache first, then SQLite, then keychain)
    info!("\x1b[35m[PROCESS]\x1b[0m Getting encryption key...");
    let cached_db_key = *state.db_encryption_key.lock().unwrap();
    let encryption_key = {
        let conn = match state.db.get() {
            Ok(c) => c,
            Err(e) => {
                error!("\x1b[31m[PROCESS]\x1b[0m Database connection error: {}", e);
                return;
            }
        };
        let secrets = state.secrets.lock().unwrap();
        state
            .session_secret_cache
            .get(&conn, &secrets, &session_id, cached_db_key.as_ref())
    };

    let encryption_key = match encryption_key {
        Some(key) => {
            info!("\x1b[35m[PROCESS]\x1b[0m Found existing encryption key");
            key
        }
        None => {
            info!("\x1b[35m[PROCESS]\x1b[0m No existing key, creating new session secret...");
            let new_secret = daemon_storage::SecretsManager::generate_session_secret();

            let db_key = match cached_db_key {
                Some(key) => {
                    info!("\x1b[35m[PROCESS]\x1b[0m Using cached database encryption key");
                    key
                }
                None => {
                    error!("\x1b[31m[PROCESS]\x1b[0m No database encryption key available (no device key?)");
                    return;
                }
            };

            let nonce = daemon_database::generate_nonce();
            let encrypted_secret = match daemon_database::encrypt_content(
                &db_key,
                &nonce,
                new_secret.as_bytes(),
            ) {
                Ok(e) => e,
                Err(e) => {
                    error!(
                        "\x1b[31m[PROCESS]\x1b[0m Failed to encrypt session secret: {}",
                        e
                    );
                    return;
                }
            };

            {
                let conn = match state.db.get() {
                    Ok(c) => c,
                    Err(e) => {
                        error!("\x1b[31m[PROCESS]\x1b[0m Database connection error: {}", e);
                        return;
                    }
                };
                if let Err(e) = queries::set_session_secret(
                    &conn,
                    &daemon_database::NewSessionSecret {
                        session_id: session_id.clone(),
                        encrypted_secret,
                        nonce: nonce.to_vec(),
                    },
                ) {
                    error!(
                        "\x1b[31m[PROCESS]\x1b[0m Failed to store session secret: {}",
                        e
                    );
                    return;
                }
            }

            match daemon_storage::SecretsManager::parse_session_secret(&new_secret) {
                Ok(key) => {
                    info!("\x1b[35m[PROCESS]\x1b[0m Created and stored new session secret");
                    key
                }
                Err(e) => {
                    error!(
                        "\x1b[31m[PROCESS]\x1b[0m Failed to parse session secret: {}",
                        e
                    );
                    return;
                }
            }
        }
    };

    // Set agent status to running
    {
        let conn = match state.db.get() {
            Ok(c) => c,
            Err(e) => {
                error!("\x1b[31m[PROCESS]\x1b[0m Database connection error: {}", e);
                return;
            }
        };
        let _ = queries::get_or_create_session_state(&conn, &session_id);
        let _ = queries::update_agent_status(&conn, &session_id, AgentStatus::Running);
        info!("\x1b[35m[PROCESS]\x1b[0m Agent status set to RUNNING");
    }

    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => {
            error!("\x1b[31m[PROCESS]\x1b[0m Failed to get stdout from Claude process");
            return;
        }
    };

    let stderr = child.stderr.take();

    let mut reader = BufReader::new(stdout).lines();
    let mut event_count = 0;

    info!("\x1b[35m[PROCESS]\x1b[0m Starting to read Claude stdout...");

    loop {
        tokio::select! {
            // Check for stop signal
            _ = stop_rx.recv() => {
                info!("\x1b[33m[PROCESS]\x1b[0m Stop signal received - killing process");
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
                            debug!("\x1b[90m[PROCESS]\x1b[0m Skipping non-JSON line: {}",
                                if clean_line.len() > 80 { &clean_line[..80] } else { &clean_line });
                            continue;
                        }

                        // Try to parse as JSON
                        let json = match serde_json::from_str::<serde_json::Value>(&clean_line) {
                            Ok(j) => j,
                            Err(e) => {
                                warn!("\x1b[33m[PROCESS]\x1b[0m Failed to parse JSON: {}", e);
                                continue;
                            }
                        };

                        event_count += 1;
                        let event_type = json.get("type").and_then(|v| v.as_str()).unwrap_or("unknown");

                        // Store raw JSON as a message with role = event type
                        let msg_sequence = {
                            let conn = match state.db.get() {
                                Ok(c) => c,
                                Err(e) => {
                                    error!("\x1b[31m[PROCESS]\x1b[0m Database connection error: {}", e);
                                    continue;
                                }
                            };
                            let sequence = match queries::get_next_message_sequence(&conn, &session_id) {
                                Ok(s) => s,
                                Err(e) => {
                                    error!("\x1b[31m[PROCESS]\x1b[0m Failed to get message sequence: {}", e);
                                    continue;
                                }
                            };

                            let nonce = daemon_database::generate_nonce();
                            let encrypted = match daemon_database::encrypt_content(
                                &encryption_key,
                                &nonce,
                                clean_line.as_bytes(),
                            ) {
                                Ok(e) => e,
                                Err(e) => {
                                    error!("\x1b[31m[PROCESS]\x1b[0m Failed to encrypt message: {}", e);
                                    continue;
                                }
                            };

                            let msg = daemon_database::NewAgentCodingSessionMessage {
                                id: uuid::Uuid::new_v4().to_string(),
                                session_id: session_id.clone(),
                                content_encrypted: encrypted,
                                content_nonce: nonce.to_vec(),
                                sequence_number: sequence,
                                is_streaming: false,
                                debugging_decrypted_payload: Some(clean_line.clone()),
                            };

                            if let Err(e) = queries::insert_message(&conn, &msg) {
                                warn!("\x1b[33m[PROCESS]\x1b[0m Failed to store message: {}", e);
                                continue;
                            }

                            sequence
                        };

                        // Log the event
                        match event_type {
                            "system" => {
                                if let Some(new_session_id) = json.get("session_id").and_then(|v| v.as_str()) {
                                    if let Ok(conn) = state.db.get() {
                                        let _ = queries::update_session_claude_id(&conn, &session_id, new_session_id);
                                    }
                                    info!("\x1b[32m[EVENT #{}]\x1b[0m \x1b[1msystem\x1b[0m - Claude session: {}", event_count, new_session_id);
                                } else {
                                    let subtype = json.get("subtype").and_then(|v| v.as_str());
                                    info!("\x1b[32m[EVENT #{}]\x1b[0m \x1b[1msystem\x1b[0m {:?}", event_count, subtype);
                                }
                            }
                            "assistant" => {
                                info!("\x1b[34m[EVENT #{}]\x1b[0m \x1b[1massistant\x1b[0m", event_count);
                            }
                            "user" => {
                                info!("\x1b[33m[EVENT #{}]\x1b[0m \x1b[1muser\x1b[0m", event_count);
                            }
                            "result" => {
                                let is_error = json.get("is_error").and_then(|v| v.as_bool()).unwrap_or(false);
                                if is_error {
                                    warn!("\x1b[31m[EVENT #{}]\x1b[0m \x1b[1mresult\x1b[0m (error)", event_count);
                                } else {
                                    info!("\x1b[32m[EVENT #{}]\x1b[0m \x1b[1mresult\x1b[0m (success)", event_count);
                                }
                            }
                            _ => {
                                debug!("\x1b[90m[EVENT #{}]\x1b[0m {}", event_count, event_type);
                            }
                        }

                        // Write to shared memory stream for clients
                        if let Some(ref producer) = stream_producer {
                            if let Err(e) = producer.write_event(
                                StreamEventType::ClaudeEvent,
                                msg_sequence,
                                clean_line.as_bytes(),
                            ) {
                                warn!(
                                    "\x1b[33m[PROCESS]\x1b[0m Shared memory write failed: {}",
                                    e
                                );
                            }
                        }

                        // Handle result event - update agent status
                        if event_type == "result" {
                            if let Ok(conn) = state.db.get() {
                                let _ = queries::update_agent_status(&conn, &session_id, AgentStatus::Idle);
                            }
                        }
                    }
                    Ok(None) => {
                        // EOF - process finished
                        info!("\x1b[35m[PROCESS]\x1b[0m Claude stdout closed (EOF)");
                        break;
                    }
                    Err(e) => {
                        error!("\x1b[31m[PROCESS]\x1b[0m Error reading Claude stdout: {}", e);
                        break;
                    }
                }
            }
        }
    }

    info!(
        "\x1b[35m[PROCESS]\x1b[0m Processed {} events total",
        event_count
    );

    // Read any remaining stderr
    if let Some(stderr) = stderr {
        let mut stderr_reader = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = stderr_reader.next_line().await {
            warn!("\x1b[31m[STDERR]\x1b[0m {}", line);
        }
    }

    // Wait for process to finish
    match child.wait().await {
        Ok(status) => {
            if status.success() {
                info!("\x1b[32m[PROCESS]\x1b[0m Claude process finished successfully");
            } else {
                warn!(
                    "\x1b[33m[PROCESS]\x1b[0m Claude process exited with status: {:?}",
                    status
                );
            }
        }
        Err(e) => {
            error!(
                "\x1b[31m[PROCESS]\x1b[0m Error waiting for Claude process: {}",
                e
            );
        }
    }

    // Update agent status to idle
    {
        if let Ok(conn) = state.db.get() {
            let _ = queries::update_agent_status(&conn, &session_id, AgentStatus::Idle);
        }
        info!("\x1b[35m[PROCESS]\x1b[0m Agent status set to IDLE");
    }

    // Remove from running processes
    {
        let mut processes = state.claude_processes.lock().unwrap();
        processes.remove(&session_id);
        info!(
            "\x1b[35m[PROCESS]\x1b[0m Cleaned up process for session: {}",
            session_id
        );
    }

    // Cleanup shared memory stream producer
    if stream_producer.is_some() {
        let mut producers = state.stream_producers.lock().unwrap();
        if let Some(producer) = producers.remove(&session_id) {
            // Shutdown signals consumers before dropping
            producer.shutdown();
            info!(
                "\x1b[35m[PROCESS]\x1b[0m Cleaned up shared memory stream for session: {}",
                session_id
            );
        }
    }
}
