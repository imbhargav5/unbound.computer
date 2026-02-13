//! Terminal handlers.

use crate::app::DaemonState;
use crate::machines::terminal::handle_terminal_process;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use sakura_working_dir_resolution::{resolve_working_dir_from_str, ResolveError};
use std::process::Stdio;
use tokio::process::Command;
use tokio::sync::broadcast;

/// Register terminal handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_terminal_run(server, state.clone()).await;
    register_terminal_status(server, state.clone()).await;
    register_terminal_stop(server, state).await;
}

async fn register_terminal_run(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::TerminalRun, move |req| {
            let state = state.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let command = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("command"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let working_dir = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("working_dir"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let (Some(session_id), Some(command)) = (session_id, command) else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id and command are required",
                    );
                };

                // Determine working directory
                let working_dir = if let Some(dir) = working_dir {
                    dir
                } else {
                    match resolve_working_dir_from_str(&*state.armin, &session_id) {
                        Ok(resolved) => resolved.working_dir,
                        Err(err) => return terminal_resolve_error_response(&req.id, err),
                    }
                };

                // Check if already running a command for this session
                {
                    let processes = state.terminal_processes.lock().unwrap();
                    if processes.contains_key(&session_id) {
                        return Response::error(
                            &req.id,
                            error_codes::INVALID_REQUEST,
                            "Terminal already running for this session",
                        );
                    }
                }

                // Spawn the command using shell
                let child = match Command::new("zsh")
                    .args(["-l", "-c", &command])
                    .current_dir(&working_dir)
                    .stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::piped())
                    .spawn()
                {
                    Ok(c) => c,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to spawn command: {}", e),
                        )
                    }
                };

                let pid = child.id();

                // Create stop channel
                let (stop_tx, _) = broadcast::channel::<()>(1);

                // Store the stop sender
                {
                    let mut processes = state.terminal_processes.lock().unwrap();
                    processes.insert(session_id.clone(), stop_tx.clone());
                }

                // Spawn task to handle output
                let state_for_task = state.clone();
                let session_id_for_task = session_id.clone();
                tokio::spawn(async move {
                    handle_terminal_process(child, session_id_for_task, state_for_task, stop_tx)
                        .await;
                });

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "started": true,
                        "pid": pid,
                    }),
                )
            }
        })
        .await;
}

fn terminal_resolve_error_response(id: &str, err: ResolveError) -> Response {
    match err {
        ResolveError::SessionNotFound(message) | ResolveError::RepositoryNotFound(message) => {
            Response::error(id, error_codes::NOT_FOUND, &message)
        }
        ResolveError::LegacyWorktreeUnsupported(message) => Response::error_with_data(
            id,
            error_codes::INTERNAL_ERROR,
            &message,
            serde_json::json!({
                "machine_code": "legacy_worktree_unsupported",
            }),
        ),
        ResolveError::Armin(err) => Response::error(
            id,
            error_codes::INTERNAL_ERROR,
            &format!("Failed to resolve working directory: {}", err),
        ),
    }
}

async fn register_terminal_status(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::TerminalStatus, move |req| {
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
                    let processes = state.terminal_processes.lock().unwrap();
                    processes.contains_key(&session_id)
                };

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "session_id": session_id,
                        "is_running": is_running,
                    }),
                )
            }
        })
        .await;
}

async fn register_terminal_stop(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::TerminalStop, move |req| {
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
                    let mut processes = state.terminal_processes.lock().unwrap();
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
                            "message": "No running terminal for this session",
                        }),
                    )
                }
            }
        })
        .await;
}
