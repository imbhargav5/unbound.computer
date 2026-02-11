//! Claude CLI handlers.

use crate::app::DaemonState;
use crate::machines::claude::handle_claude_events;
use armin::{NewMessage, SessionId, SessionReader, SessionWriter};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use deku::{ClaudeConfig, ClaudeProcess};
use tracing::{info, warn};

/// Register Claude handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_claude_send(server, state.clone()).await;
    register_claude_status(server, state.clone()).await;
    register_claude_stop(server, state).await;
}

/// Core claude.send logic shared by IPC and remote command paths.
pub async fn claude_send_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, (String, String)> {
    info!("Received claude.send request");

    let session_id = params.get("session_id").and_then(|v| v.as_str()).map(String::from);
    let content = params.get("content").and_then(|v| v.as_str()).map(String::from);

    let (Some(session_id), Some(content)) = (session_id, content) else {
        return Err(("invalid_params".to_string(), "session_id and content are required".to_string()));
    };

    info!(session_id = %session_id, content_len = content.len(), "claude.send params");

    // Get session and repository to find working directory
    let (working_dir, claude_session_id) = {
        let armin_session_id = SessionId::from_string(&session_id);
        let session = match state.armin.get_session(&armin_session_id) {
            Ok(Some(s)) => s,
            Ok(None) => {
                return Err(("not_found".to_string(), "Session not found".to_string()));
            }
            Err(e) => {
                return Err(("internal_error".to_string(), format!("Failed to get session: {}", e)));
            }
        };

        let repo = match state.armin.get_repository(&session.repository_id) {
            Ok(Some(r)) => r,
            Ok(None) => {
                return Err(("not_found".to_string(), "Repository not found".to_string()));
            }
            Err(e) => {
                return Err(("internal_error".to_string(), format!("Failed to get repository: {}", e)));
            }
        };

        let working_dir = session.worktree_path.unwrap_or(repo.path);
        (working_dir, session.claude_session_id)
    };

    info!(working_dir = %working_dir, "claude.send working directory");

    // Store the user message via Armin
    {
        let armin_session_id = SessionId::from_string(&session_id);
        match state.armin.append(
            &armin_session_id,
            NewMessage {
                content: content.clone(),
            },
        ) {
            Ok(message) => {
                info!(seq = message.sequence_number, "Stored user message via Armin");
            }
            Err(e) => {
                warn!("Failed to store user message: {}", e);
            }
        }
    }

    // Build Claude configuration using Deku
    let mut config = ClaudeConfig::new(&content, &working_dir);
    if let Some(ref prev_session_id) = claude_session_id {
        info!(prev_session_id = %prev_session_id, "Resuming previous Claude session");
        config = config.with_resume_session(prev_session_id);
    } else {
        info!("Starting new Claude session");
    }

    // Spawn the Claude process using Deku
    let mut process = match ClaudeProcess::spawn(config).await {
        Ok(p) => {
            info!(pid = ?p.pid(), "Claude process spawned");
            p
        }
        Err(e) => {
            return Err(("internal_error".to_string(), format!("Failed to spawn claude: {}", e)));
        }
    };

    let stop_tx = process.stop_sender();
    let stream = match process.take_stream() {
        Some(s) => s,
        None => {
            return Err(("internal_error".to_string(), "Failed to get event stream".to_string()));
        }
    };

    {
        let mut processes = state.claude_processes.lock().unwrap();
        processes.insert(session_id.clone(), stop_tx);
    }

    let state_for_task = state.clone();
    let session_id_for_task = session_id.clone();

    tokio::spawn(async move {
        handle_claude_events(stream, session_id_for_task, state_for_task).await;
    });

    info!(session_id = %session_id, "claude.send completed - process running in background");

    Ok(serde_json::json!({
        "status": "started",
        "session_id": session_id,
    }))
}

/// Core claude.stop logic shared by IPC and remote command paths.
pub async fn claude_stop_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, (String, String)> {
    let session_id = params.get("session_id").and_then(|v| v.as_str()).map(String::from);

    let Some(session_id) = session_id else {
        return Err(("invalid_params".to_string(), "session_id is required".to_string()));
    };

    let stop_tx = {
        let mut processes = state.claude_processes.lock().unwrap();
        processes.remove(&session_id)
    };

    if let Some(tx) = stop_tx {
        let _ = tx.send(());
        Ok(serde_json::json!({
            "session_id": session_id,
            "stopped": true,
        }))
    } else {
        Ok(serde_json::json!({
            "session_id": session_id,
            "stopped": false,
            "message": "No running Claude process for this session",
        }))
    }
}

async fn register_claude_send(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::ClaudeSend, move |req| {
            let state = state.clone();
            async move {
                let params = req.params.as_ref().cloned().unwrap_or(serde_json::json!({}));
                match claude_send_core(&state, &params).await {
                    Ok(data) => Response::success(&req.id, data),
                    Err((code, msg)) => {
                        let error_code = match code.as_str() {
                            "invalid_params" => error_codes::INVALID_PARAMS,
                            "not_found" => error_codes::NOT_FOUND,
                            _ => error_codes::INTERNAL_ERROR,
                        };
                        Response::error(&req.id, error_code, &msg)
                    }
                }
            }
        })
        .await;
}

async fn register_claude_status(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::ClaudeStatus, move |req| {
            let state = state.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let Some(session_id) = session_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id is required",
                    );
                };

                let is_running = {
                    let processes = state.claude_processes.lock().unwrap();
                    processes.contains_key(&session_id)
                };

                // Get agent status from Armin
                let armin_session_id = SessionId::from_string(&session_id);
                let agent_status = state
                    .armin
                    .get_session_state(&armin_session_id)
                    .ok()
                    .flatten()
                    .map(|s| s.agent_status.as_str().to_string())
                    .unwrap_or_else(|| "idle".to_string());

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "session_id": session_id,
                        "is_running": is_running,
                        "agent_status": agent_status,
                    }),
                )
            }
        })
        .await;
}

async fn register_claude_stop(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::ClaudeStop, move |req| {
            let state = state.clone();
            async move {
                let params = req.params.as_ref().cloned().unwrap_or(serde_json::json!({}));
                match claude_stop_core(&state, &params).await {
                    Ok(data) => Response::success(&req.id, data),
                    Err((code, msg)) => {
                        let error_code = match code.as_str() {
                            "invalid_params" => error_codes::INVALID_PARAMS,
                            "not_found" => error_codes::NOT_FOUND,
                            _ => error_codes::INTERNAL_ERROR,
                        };
                        Response::error(&req.id, error_code, &msg)
                    }
                }
            }
        })
        .await;
}
