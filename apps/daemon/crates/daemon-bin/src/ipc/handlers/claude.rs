//! Claude CLI handlers.

use crate::app::DaemonState;
use crate::machines::claude::handle_claude_events;
use armin::{NewMessage, SessionId, SessionReader, SessionWriter};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use deku::{ClaudeConfig, ClaudeProcess};
use tracing::{error, info, warn};

/// Register Claude handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_claude_send(server, state.clone()).await;
    register_claude_status(server, state.clone()).await;
    register_claude_stop(server, state).await;
}

async fn register_claude_send(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::ClaudeSend, move |req| {
            let state = state.clone();
            async move {
                info!("\x1b[36m[CLAUDE]\x1b[0m Received claude.send request");

                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let content = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("content"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let (Some(session_id), Some(content)) = (session_id, content) else {
                    error!("\x1b[31m[CLAUDE]\x1b[0m Missing session_id or content");
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id and content are required",
                    );
                };

                info!(
                    "\x1b[36m[CLAUDE]\x1b[0m Session: {}, Content length: {} chars",
                    session_id,
                    content.len()
                );

                // Get session and repository to find working directory
                let (working_dir, claude_session_id) = {
                    let armin_session_id = SessionId::from_string(&session_id);
                    let session = match state.armin.get_session(&armin_session_id) {
                        Ok(Some(s)) => s,
                        Ok(None) => {
                            error!("\x1b[31m[CLAUDE]\x1b[0m Session not found: {}", session_id);
                            return Response::error(
                                &req.id,
                                error_codes::NOT_FOUND,
                                "Session not found",
                            );
                        }
                        Err(e) => {
                            error!("\x1b[31m[CLAUDE]\x1b[0m Failed to get session: {}", e);
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &format!("Failed to get session: {}", e),
                            );
                        }
                    };

                    info!(
                        "\x1b[36m[CLAUDE]\x1b[0m Found session: {} (repo: {})",
                        session.title,
                        session.repository_id.as_str()
                    );

                    let repo = match state.armin.get_repository(&session.repository_id) {
                        Ok(Some(r)) => r,
                        Ok(None) => {
                            error!(
                                "\x1b[31m[CLAUDE]\x1b[0m Repository not found: {}",
                                session.repository_id.as_str()
                            );
                            return Response::error(
                                &req.id,
                                error_codes::NOT_FOUND,
                                "Repository not found",
                            );
                        }
                        Err(e) => {
                            error!("\x1b[31m[CLAUDE]\x1b[0m Failed to get repository: {}", e);
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &format!("Failed to get repository: {}", e),
                            );
                        }
                    };

                    info!(
                        "\x1b[36m[CLAUDE]\x1b[0m Found repository: {} ({})",
                        repo.name, repo.path
                    );

                    // Use worktree path if available, otherwise repository path
                    let working_dir = session.worktree_path.unwrap_or(repo.path);
                    (working_dir, session.claude_session_id)
                };

                info!("\x1b[33m[CLAUDE]\x1b[0m Working directory: {}", working_dir);

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
                                "\x1b[32m[CLAUDE]\x1b[0m Stored user message via Armin (seq: {})",
                                message.sequence_number
                            );
                        }
                        Err(e) => {
                            warn!(
                                "\x1b[31m[CLAUDE]\x1b[0m Failed to store user message: {}",
                                e
                            );
                        }
                    }
                }

                // Build Claude configuration using Deku
                let mut config = ClaudeConfig::new(&content, &working_dir);
                if let Some(ref prev_session_id) = claude_session_id {
                    info!(
                        "\x1b[36m[CLAUDE]\x1b[0m Resuming previous session: {}",
                        prev_session_id
                    );
                    config = config.with_resume_session(prev_session_id);
                } else {
                    info!("\x1b[36m[CLAUDE]\x1b[0m Starting new Claude session");
                }

                // Spawn the Claude process using Deku
                let mut process = match ClaudeProcess::spawn(config).await {
                    Ok(p) => {
                        info!(
                            "\x1b[32m[CLAUDE]\x1b[0m Process spawned successfully (PID: {:?})",
                            p.pid()
                        );
                        p
                    }
                    Err(e) => {
                        error!("\x1b[31m[CLAUDE]\x1b[0m Failed to spawn Claude CLI: {}", e);
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to spawn claude: {}", e),
                        );
                    }
                };

                // Get the stop sender and event stream
                let stop_tx = process.stop_sender();
                let stream = match process.take_stream() {
                    Some(s) => s,
                    None => {
                        error!("\x1b[31m[CLAUDE]\x1b[0m Failed to get event stream");
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            "Failed to get event stream",
                        );
                    }
                };

                // Store the stop sender
                {
                    let mut processes = state.claude_processes.lock().unwrap();
                    processes.insert(session_id.clone(), stop_tx);
                    info!(
                        "\x1b[36m[CLAUDE]\x1b[0m Registered process for session: {}",
                        session_id
                    );
                }

                // Spawn a task to handle the process events
                let state_for_task = state.clone();
                let session_id_for_task = session_id.clone();

                tokio::spawn(async move {
                    handle_claude_events(stream, session_id_for_task, state_for_task).await;
                });

                info!(
                    "\x1b[32m[CLAUDE]\x1b[0m claude.send completed - process running in background"
                );

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "status": "started",
                        "session_id": session_id,
                    }),
                )
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

                let stop_tx = {
                    let mut processes = state.claude_processes.lock().unwrap();
                    processes.remove(&session_id)
                };

                if let Some(tx) = stop_tx {
                    let _ = tx.send(());
                    Response::success(
                        &req.id,
                        serde_json::json!({
                            "session_id": session_id,
                            "stopped": true,
                        }),
                    )
                } else {
                    Response::success(
                        &req.id,
                        serde_json::json!({
                            "session_id": session_id,
                            "stopped": false,
                            "message": "No running Claude process for this session",
                        }),
                    )
                }
            }
        })
        .await;
}
