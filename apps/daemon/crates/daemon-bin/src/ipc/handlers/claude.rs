//! Claude CLI handlers.

use crate::app::DaemonState;
use crate::machines::claude::handle_claude_events;
use armin::{NewMessage, SessionId, SessionReader, SessionWriter};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use deku::{ClaudeConfig, ClaudeProcess, PermissionMode};
use sakura_working_dir_resolution::{resolve_working_dir_from_str, ResolveError};
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

    let session_id = params
        .get("session_id")
        .and_then(|v| v.as_str())
        .map(String::from);
    let content = params
        .get("content")
        .and_then(|v| v.as_str())
        .map(String::from);
    let permission_mode = parse_permission_mode(params)?;

    let (Some(session_id), Some(content)) = (session_id, content) else {
        return Err((
            "invalid_params".to_string(),
            "session_id and content are required".to_string(),
        ));
    };

    info!(session_id = %session_id, content_len = content.len(), "claude.send params");

    let resolved_workspace =
        resolve_working_dir_from_str(&*state.armin, &session_id).map_err(map_resolve_error)?;
    let working_dir = resolved_workspace.working_dir;
    let claude_session_id = resolved_workspace.session.claude_session_id;

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
                info!(
                    seq = message.sequence_number,
                    "Stored user message via Armin"
                );
            }
            Err(e) => {
                warn!("Failed to store user message: {}", e);
            }
        }
    }

    // Build Claude configuration using Deku
    let mut config = ClaudeConfig::new(&content, &working_dir);
    if let Some(permission_mode) = permission_mode {
        config = config.with_permission_mode(permission_mode);
    }
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
            return Err((
                "internal_error".to_string(),
                format!("Failed to spawn claude: {}", e),
            ));
        }
    };

    let stop_tx = process.stop_sender();
    let stream = match process.take_stream() {
        Some(s) => s,
        None => {
            return Err((
                "internal_error".to_string(),
                "Failed to get event stream".to_string(),
            ));
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
    let session_id = params
        .get("session_id")
        .and_then(|v| v.as_str())
        .map(String::from);

    let Some(session_id) = session_id else {
        return Err((
            "invalid_params".to_string(),
            "session_id is required".to_string(),
        ));
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
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match claude_send_core(&state, &params).await {
                    Ok(data) => Response::success(&req.id, data),
                    Err((code, msg)) => {
                        let error_code = match code.as_str() {
                            "invalid_params" => error_codes::INVALID_PARAMS,
                            "not_found" => error_codes::NOT_FOUND,
                            _ => error_codes::INTERNAL_ERROR,
                        };
                        if code == "legacy_worktree_unsupported" {
                            Response::error_with_data(
                                &req.id,
                                error_code,
                                &msg,
                                serde_json::json!({
                                    "machine_code": "legacy_worktree_unsupported",
                                }),
                            )
                        } else {
                            Response::error(&req.id, error_code, &msg)
                        }
                    }
                }
            }
        })
        .await;
}

fn map_resolve_error(err: ResolveError) -> (String, String) {
    match err {
        ResolveError::SessionNotFound(message) => ("not_found".to_string(), message),
        ResolveError::RepositoryNotFound(message) => ("not_found".to_string(), message),
        ResolveError::LegacyWorktreeUnsupported(message) => {
            ("legacy_worktree_unsupported".to_string(), message)
        }
        ResolveError::Armin(err) => (
            "internal_error".to_string(),
            format!("Failed to resolve working directory: {}", err),
        ),
    }
}

fn parse_permission_mode(
    params: &serde_json::Value,
) -> Result<Option<PermissionMode>, (String, String)> {
    let permission_mode = params.get("permission_mode").and_then(|v| v.as_str());
    match permission_mode {
        None => Ok(None),
        Some("plan") => Ok(Some(PermissionMode::Plan)),
        Some(_) => Err((
            "invalid_params".to_string(),
            "permission_mode must be \"plan\" when provided".to_string(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_permission_mode_missing() {
        let parsed = parse_permission_mode(&json!({}));
        assert_eq!(parsed, Ok(None));
    }

    #[test]
    fn parse_permission_mode_plan() {
        let parsed = parse_permission_mode(&json!({ "permission_mode": "plan" }));
        assert_eq!(parsed, Ok(Some(PermissionMode::Plan)));
    }

    #[test]
    fn parse_permission_mode_invalid() {
        let parsed = parse_permission_mode(&json!({ "permission_mode": "something" }));
        assert_eq!(
            parsed,
            Err((
                "invalid_params".to_string(),
                "permission_mode must be \"plan\" when provided".to_string()
            ))
        );
    }
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
                    .map(|s| s.runtime_status.coding_session.status.as_str().to_string())
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
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
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
