//! Claude CLI handlers.

use crate::app::agent_cli::{
    build_agent_cli_config_from_adapter, detect_agent_cli_kind, AgentCliEvent, AgentCliKind,
    AgentCliProcess,
};
use crate::app::DaemonState;
use crate::machines::claude::handle_claude_events;
use crate::observability::{current_trace_context, spawn_in_current_span};
use agent_session_sqlite_persist_core::{
    CodingSessionStatus, NewMessage, Session, SessionId, SessionReader, SessionWriter,
};
use claude_process_manager::{ClaudeConfig, ClaudeProcess, PermissionMode};
use daemon_board::service;
use daemon_ipc::{error_codes, Event, EventType, IpcServer, Method, Response};
use serde_json::Value;
use std::sync::atomic::{AtomicI64, Ordering};
use tracing::{info, warn, Instrument};
use workspace_resolver::{resolve_working_dir_from_str, ResolveError};

static AGENT_STREAM_SEQUENCE: AtomicI64 = AtomicI64::new(0);

/// Register Claude handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_agent_send(server, state.clone()).await;
    register_agent_status(server, state.clone()).await;
    register_agent_stop(server, state.clone()).await;
    register_claude_send(server, state.clone()).await;
    register_claude_status(server, state.clone()).await;
    register_claude_stop(server, state).await;
}

pub async fn agent_send_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, (String, String)> {
    let session_id = params
        .get("session_id")
        .and_then(|v| v.as_str())
        .map(String::from);
    let content = params
        .get("content")
        .and_then(|v| v.as_str())
        .map(String::from);
    let requested_provider = params
        .get("provider")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase());
    let permission_mode = parse_permission_mode(params)?;

    let (Some(session_id), Some(content)) = (session_id, content) else {
        return Err((
            "invalid_params".to_string(),
            "session_id and content are required".to_string(),
        ));
    };

    let resolved_workspace = async {
        resolve_working_dir_from_str(&*state.armin, &session_id).map_err(map_resolve_error)
    }
    .instrument(tracing::info_span!(
        "workspace.resolve",
        session_id = %session_id,
        feature = "agent.send"
    ))
    .await?;

    let session = resolved_workspace.session;
    let working_dir = resolved_workspace.working_dir;
    let agent = match session.agent_id.as_deref() {
        Some(agent_id) => service::get_agent(&state.db, agent_id)
            .await
            .map_err(|error| ("internal_error".to_string(), error.to_string()))?,
        None => None,
    };
    let cli_kind = match requested_provider.as_deref() {
        Some("claude") => AgentCliKind::Claude,
        Some("codex") => AgentCliKind::Codex,
        Some(_) => {
            return Err((
                "invalid_params".to_string(),
                "provider must be either \"claude\" or \"codex\" when provided".to_string(),
            ))
        }
        None => detect_cli_kind_for_session(&session, agent.as_ref()),
    };

    if cli_kind == AgentCliKind::Claude {
        return claude_send_core(state, params).await;
    }

    if permission_mode.is_some() {
        return Err((
            "invalid_params".to_string(),
            "permission_mode is only supported for Claude sessions".to_string(),
        ));
    }

    append_session_message(state, &session_id, &content, "user_input");

    let mut config = build_agent_cli_config_from_adapter(
        agent
            .as_ref()
            .and_then(|agent| agent.adapter_config.as_object()),
        None,
        &content,
        working_dir,
        codex_resume_session_id(&session),
    );
    if config.kind != AgentCliKind::Codex {
        config.kind = AgentCliKind::Codex;
        if config.executable.trim().is_empty() || config.executable == "claude" {
            config.executable = "codex".to_string();
        }
    }

    let mut process = AgentCliProcess::spawn(config).await.map_err(|error| {
        (
            "internal_error".to_string(),
            format!("Failed to spawn Codex: {error}"),
        )
    })?;

    let stop_tx = process.stop_sender();
    let stream = process.take_stream().ok_or_else(|| {
        (
            "internal_error".to_string(),
            "Failed to get event stream".to_string(),
        )
    })?;

    {
        let mut processes = state.claude_processes.lock().unwrap();
        processes.insert(session_id.clone(), stop_tx);
    }

    let state_for_task = state.clone();
    let session_id_for_task = session_id.clone();
    spawn_in_current_span(async move {
        handle_agent_cli_session_events(
            stream,
            AgentCliKind::Codex,
            session_id_for_task,
            state_for_task,
        )
        .await;
    });

    Ok(serde_json::json!({
        "status": "started",
        "session_id": session_id,
        "provider": "codex",
    }))
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

    let resolved_workspace = async {
        resolve_working_dir_from_str(&*state.armin, &session_id).map_err(map_resolve_error)
    }
    .instrument(tracing::info_span!(
        "workspace.resolve",
        session_id = %session_id,
        feature = "claude.send"
    ))
    .await?;
    let working_dir = resolved_workspace.working_dir;
    let claude_session_id = resolved_workspace.session.claude_session_id;

    info!(working_dir = %working_dir, "claude.send working directory");

    // Store the user message via Armin
    {
        let armin_session_id = SessionId::from_string(&session_id);
        let _guard = tracing::info_span!(
            "armin.append",
            session_id = %session_id,
            message_kind = "user_input",
            feature = "claude.send"
        )
        .entered();
        match state.armin.append(
            &armin_session_id,
            NewMessage {
                content: content.clone(),
            },
        ) {
            Ok(message) => {
                info!(
                    feature = "claude.send",
                    seq = message.sequence_number,
                    "Stored user message via Armin"
                );
            }
            Err(e) => {
                warn!(
                    feature = "claude.send",
                    "Failed to store user message: {}", e
                );
            }
        }
    }

    // Build Claude configuration using claude-process-manager
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

    // Spawn the Claude process using claude-process-manager
    let mut process = match async { ClaudeProcess::spawn(config).await }
        .instrument(tracing::info_span!(
            "claude.process.spawn",
            session_id = %session_id,
            working_dir = %working_dir,
            feature = "claude.send"
        ))
        .await
    {
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

    spawn_in_current_span(async move {
        handle_claude_events(stream, session_id_for_task, state_for_task).await;
    });

    info!(
        session_id = %session_id,
        feature = "claude.send",
        result = "started",
        "claude.send completed - process running in background"
    );

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
    agent_stop_core(state, params).await
}

pub async fn agent_stop_core(
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
            "message": "No running agent process for this session",
        }))
    }
}

pub async fn agent_status_core(
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

    let is_running = {
        let processes = state.claude_processes.lock().unwrap();
        processes.contains_key(&session_id)
    };

    let armin_session_id = SessionId::from_string(&session_id);
    let agent_status = state
        .armin
        .get_session_state(&armin_session_id)
        .ok()
        .flatten()
        .map(|s| s.runtime_status.coding_session.status.as_str().to_string())
        .unwrap_or_else(|| "idle".to_string());

    Ok(serde_json::json!({
        "session_id": session_id,
        "is_running": is_running,
        "agent_status": agent_status,
    }))
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

fn detect_cli_kind_for_session(
    session: &Session,
    agent: Option<&daemon_board::Agent>,
) -> AgentCliKind {
    match session.effective_provider() {
        Some("codex") => AgentCliKind::Codex,
        Some("claude") => AgentCliKind::Claude,
        Some(_) | None => agent
            .map(|agent| {
                detect_agent_cli_kind(
                    agent.adapter_config.get("command").and_then(|v| v.as_str()),
                    agent.adapter_config.get("model").and_then(|v| v.as_str()),
                )
            })
            .unwrap_or(AgentCliKind::Claude),
    }
}

fn codex_resume_session_id(session: &Session) -> Option<&str> {
    if session.effective_provider() == Some("codex") {
        session.provider_session_id.as_deref()
    } else {
        None
    }
}

fn provider_name_for_kind(kind: AgentCliKind) -> &'static str {
    match kind {
        AgentCliKind::Claude => "claude",
        AgentCliKind::Codex => "codex",
    }
}

fn append_session_message(state: &DaemonState, session_id: &str, content: &str, kind: &str) {
    let armin_session_id = SessionId::from_string(session_id);
    let _guard = tracing::info_span!(
        "armin.append",
        session_id = %session_id,
        message_kind = kind
    )
    .entered();
    if let Err(error) = state.armin.append(
        &armin_session_id,
        NewMessage {
            content: content.to_string(),
        },
    ) {
        warn!(error = %error, message_kind = kind, "Failed to append session message");
    }
}

fn write_runtime_status(
    state: &DaemonState,
    session_id: &str,
    status: CodingSessionStatus,
    error_message: Option<String>,
) {
    let armin_session_id = SessionId::from_string(session_id);
    let device_id = {
        let guard = state.device_id.lock().unwrap();
        guard.clone()
    };
    let Some(device_id) = device_id else {
        return;
    };

    if let Err(error) =
        state
            .armin
            .update_runtime_status(&armin_session_id, &device_id, status, error_message)
    {
        warn!(error = %error, "Failed to update runtime status");
    }
}

fn broadcast_agent_event(state: &DaemonState, session_id: &str, raw_json: &str) {
    let seq = AGENT_STREAM_SEQUENCE.fetch_add(1, Ordering::SeqCst);
    let mut event = Event::new(
        EventType::AgentEvent,
        session_id,
        serde_json::json!({ "raw_json": raw_json }),
        seq,
    );
    if let Some(trace_context) = current_trace_context() {
        event = event.with_context(trace_context);
    }
    let subscriptions = state.subscriptions.clone();
    let session_id_for_broadcast = session_id.to_string();
    spawn_in_current_span(async move {
        subscriptions
            .broadcast_or_create(&session_id_for_broadcast, event)
            .await;
    });
}

async fn handle_agent_cli_session_events(
    mut stream: crate::app::agent_cli::AgentCliEventStream,
    kind: AgentCliKind,
    session_id: String,
    state: DaemonState,
) {
    write_runtime_status(&state, &session_id, CodingSessionStatus::Running, None);

    while let Some(event) = stream.next().await {
        match &event {
            AgentCliEvent::Json { raw, json } => {
                append_session_message(
                    &state,
                    &session_id,
                    raw,
                    match kind {
                        AgentCliKind::Claude => "claude_json",
                        AgentCliKind::Codex => "codex_json",
                    },
                );
                broadcast_agent_event(&state, &session_id, raw);
                if kind == AgentCliKind::Claude && is_ask_user_question(json) {
                    write_runtime_status(&state, &session_id, CodingSessionStatus::Waiting, None);
                } else {
                    write_runtime_status(&state, &session_id, CodingSessionStatus::Running, None);
                }
                if let Some(provider_session_id) = extract_provider_session_id(kind, json) {
                    let armin_session_id = SessionId::from_string(&session_id);
                    if let Err(error) = state.armin.update_session_provider_session(
                        &armin_session_id,
                        provider_name_for_kind(kind),
                        &provider_session_id,
                    ) {
                        warn!(error = %error, "Failed to update provider session id");
                    }
                }
                if let Some(error_message) = extract_process_error(kind, json) {
                    write_runtime_status(
                        &state,
                        &session_id,
                        CodingSessionStatus::Error,
                        Some(error_message),
                    );
                }
            }
            AgentCliEvent::Stderr { line } => {
                append_session_message(
                    &state,
                    &session_id,
                    line,
                    match kind {
                        AgentCliKind::Claude => "claude_stderr",
                        AgentCliKind::Codex => "codex_stderr",
                    },
                );
            }
            AgentCliEvent::Finished { success, exit_code } => {
                if *success {
                    write_runtime_status(&state, &session_id, CodingSessionStatus::Idle, None);
                } else {
                    let error_message = match exit_code {
                        Some(code) => format!(
                            "{} process exited with status {code}",
                            provider_name_for_kind(kind)
                        ),
                        None => format!(
                            "{} process exited with non-zero status",
                            provider_name_for_kind(kind)
                        ),
                    };
                    write_runtime_status(
                        &state,
                        &session_id,
                        CodingSessionStatus::Error,
                        Some(error_message),
                    );
                }
            }
            AgentCliEvent::Stopped => {
                write_runtime_status(&state, &session_id, CodingSessionStatus::NotAvailable, None);
            }
        }

        if event.is_terminal() {
            break;
        }
    }

    {
        let mut processes = state.claude_processes.lock().unwrap();
        processes.remove(&session_id);
    }
}

fn extract_provider_session_id(kind: AgentCliKind, json: &serde_json::Value) -> Option<String> {
    match kind {
        AgentCliKind::Claude => json
            .get("session_id")
            .and_then(|value| value.as_str())
            .map(ToOwned::to_owned),
        AgentCliKind::Codex => json
            .get("thread_id")
            .or_else(|| json.get("threadId"))
            .or_else(|| json.get("id"))
            .and_then(|value| value.as_str())
            .map(ToOwned::to_owned),
    }
}

fn extract_process_error(kind: AgentCliKind, json: &serde_json::Value) -> Option<String> {
    match kind {
        AgentCliKind::Claude => {
            if json.get("type").and_then(Value::as_str) == Some("result")
                && json.get("subtype").and_then(Value::as_str) == Some("error")
            {
                Some("Claude reported an error result".to_string())
            } else {
                None
            }
        }
        AgentCliKind::Codex => {
            let event_type = json.get("type").and_then(Value::as_str).unwrap_or_default();
            if event_type == "turn.failed" || event_type == "error" {
                return json
                    .get("message")
                    .or_else(|| json.get("error"))
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned)
                    .or_else(|| Some("Codex reported an error result".to_string()));
            }
            None
        }
    }
}

fn is_ask_user_question(json: &serde_json::Value) -> bool {
    json.get("type").and_then(Value::as_str) == Some("assistant")
        && json
            .get("message")
            .and_then(Value::as_object)
            .is_some_and(|message| {
                message
                    .get("content")
                    .and_then(Value::as_array)
                    .is_some_and(|content| {
                        content.iter().any(|item| {
                            item.get("type").and_then(Value::as_str) == Some("tool_use")
                                && item.get("name").and_then(Value::as_str)
                                    == Some("ask_user_question")
                        })
                    })
            })
}

async fn register_agent_send(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AgentSend, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match agent_send_core(&state, &params).await {
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

async fn register_agent_status(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AgentStatus, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match agent_status_core(&state, &params).await {
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

async fn register_agent_stop(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AgentStop, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match agent_stop_core(&state, &params).await {
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
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match agent_status_core(&state, &params).await {
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
