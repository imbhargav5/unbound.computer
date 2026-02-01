//! Claude CLI handlers.

use crate::app::DaemonState;
use crate::machines::claude::handle_claude_process;
use crate::utils::shell_escape;
use armin::{NewMessage, SessionId, SessionWriter};
use daemon_database::queries;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use std::process::Stdio;
use tokio::process::Command;
use tokio::sync::broadcast;
use tracing::{error, info};

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
                    let conn = match state.db.get() {
                        Ok(c) => c,
                        Err(e) => {
                            error!("\x1b[31m[CLAUDE]\x1b[0m Database connection error: {}", e);
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &e.to_string(),
                            );
                        }
                    };
                    let session = match queries::get_session(&conn, &session_id) {
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
                            error!("\x1b[31m[CLAUDE]\x1b[0m Database error: {}", e);
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &e.to_string(),
                            );
                        }
                    };

                    info!(
                        "\x1b[36m[CLAUDE]\x1b[0m Found session: {} (repo: {})",
                        session.title, session.repository_id
                    );

                    let repo = match queries::get_repository(&conn, &session.repository_id) {
                        Ok(Some(r)) => r,
                        Ok(None) => {
                            error!(
                                "\x1b[31m[CLAUDE]\x1b[0m Repository not found: {}",
                                session.repository_id
                            );
                            return Response::error(
                                &req.id,
                                error_codes::NOT_FOUND,
                                "Repository not found",
                            );
                        }
                        Err(e) => {
                            error!("\x1b[31m[CLAUDE]\x1b[0m Database error: {}", e);
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &e.to_string(),
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

                // Build the Claude command
                let escaped_message = shell_escape(&content);
                let allowed_tools = "AskUserQuestion,Bash,TaskOutput,Edit,ExitPlanMode,Glob,Grep,KillShell,MCPSearch,NotebookEdit,Read,Skill,Task,TaskCreate,TaskGet,TaskList,TaskUpdate,WebFetch,WebSearch,Write";

                let mut claude_cmd = format!(
                    "claude -p {} --verbose --output-format stream-json --allowedTools {}",
                    escaped_message, allowed_tools
                );

                // Add resume flag if we have a previous Claude session ID
                if let Some(ref prev_session_id) = claude_session_id {
                    info!(
                        "\x1b[36m[CLAUDE]\x1b[0m Resuming previous session: {}",
                        prev_session_id
                    );
                    claude_cmd.push_str(&format!(" -r {}", prev_session_id));
                } else {
                    info!("\x1b[36m[CLAUDE]\x1b[0m Starting new Claude session");
                }

                info!("\x1b[33m[CLAUDE]\x1b[0m Working directory: {}", working_dir);
                info!("\x1b[33m[CLAUDE]\x1b[0m Command: zsh -l -c \"claude -p <message> --verbose --output-format stream-json ...\"");

                // Store the user message via Armin
                {
                    let armin_session_id = SessionId::from_string(&session_id);
                    let message = state.armin.append(
                        &armin_session_id,
                        NewMessage {
                            content: content.clone(),
                        },
                    );
                    info!(
                        "\x1b[32m[CLAUDE]\x1b[0m Stored user message via Armin (seq: {})",
                        message.sequence_number
                    );
                }

                // Note: User message is stored in database above. Clients receive
                // it when they fetch messages. We don't broadcast via socket since
                // all streaming now uses shared memory for low latency.

                // Spawn the process
                let child = match Command::new("zsh")
                    .args(["-l", "-c", &claude_cmd])
                    .current_dir(&working_dir)
                    .stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::piped())
                    .spawn()
                {
                    Ok(c) => {
                        info!(
                            "\x1b[32m[CLAUDE]\x1b[0m Process spawned successfully (PID: {:?})",
                            c.id()
                        );
                        c
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

                // Create stop channel
                let (stop_tx, _) = broadcast::channel::<()>(1);

                // Store the stop sender
                {
                    let mut processes = state.claude_processes.lock().unwrap();
                    processes.insert(session_id.clone(), stop_tx.clone());
                    info!(
                        "\x1b[36m[CLAUDE]\x1b[0m Registered process for session: {}",
                        session_id
                    );
                }

                // Spawn a task to handle the process output
                let state_for_task = state.clone();
                let session_id_for_task = session_id.clone();
                let req_id = req.id.clone();

                tokio::spawn(async move {
                    handle_claude_process(child, session_id_for_task, state_for_task, stop_tx).await;
                });

                info!("\x1b[32m[CLAUDE]\x1b[0m claude.send completed - process running in background");

                Response::success(
                    &req_id,
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

                // Get agent status from database
                let agent_status = {
                    match state.db.get() {
                        Ok(conn) => queries::get_session_state(&conn, &session_id)
                            .ok()
                            .flatten()
                            .map(|s| s.agent_status.as_str().to_string())
                            .unwrap_or_else(|| "idle".to_string()),
                        Err(_) => "idle".to_string(),
                    }
                };

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
