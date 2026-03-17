use crate::compatibility::{self, DesktopBootstrapStatus};
use daemon_ipc::{DaemonVersionInfo, IpcClient, Method};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use tauri::async_runtime::JoinHandle;
use tauri::{AppHandle, Emitter, State};
use url::Url;

#[derive(Default)]
pub struct DesktopState {
    subscriptions: Mutex<HashMap<String, JoinHandle<()>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DashboardProjectViewSettings {
    pub group_by: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DesktopSettings {
    pub preferred_company_id: Option<String>,
    pub preferred_repository_id: Option<String>,
    pub preferred_view: Option<String>,
    pub show_raw_message_json: bool,
    pub last_repository_path: Option<String>,
    pub theme_mode: Option<String>,
    pub font_size_preset: Option<String>,
    pub dashboard_project_views: Option<HashMap<String, DashboardProjectViewSettings>>,
}

impl Default for DesktopSettings {
    fn default() -> Self {
        Self {
            preferred_company_id: None,
            preferred_repository_id: None,
            preferred_view: Some("dashboard".to_string()),
            show_raw_message_json: false,
            last_repository_path: None,
            theme_mode: Some("dark".to_string()),
            font_size_preset: Some("medium".to_string()),
            dashboard_project_views: Some(HashMap::new()),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
struct SessionStreamPayload {
    session_id: String,
    event: Value,
}

fn ipc_client() -> IpcClient {
    let runtime_paths = compatibility::resolve_runtime_paths();
    compatibility::ipc_client(&runtime_paths)
}

fn settings_path() -> PathBuf {
    compatibility::resolve_runtime_paths()
        .base_dir
        .join("desktop-settings.json")
}

async fn call_daemon(method: Method, params: Option<Value>) -> Result<Value, String> {
    let client = ipc_client();
    let response = match params {
        Some(params) => client
            .call_method_with_params(method, params)
            .await
            .map_err(|error| error.to_string())?,
        None => client
            .call_method(method)
            .await
            .map_err(|error| error.to_string())?,
    };

    if let Some(error) = response.error {
        return Err(error.message);
    }

    Ok(response.result.unwrap_or_else(|| json!({})))
}

fn extract_field(value: Value, field: &str) -> Value {
    value.get(field).cloned().unwrap_or(Value::Null)
}

fn derive_repository_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .and_then(|value| value.to_str())
        .map(ToOwned::to_owned)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "Repository".to_string())
}

fn read_settings() -> Result<DesktopSettings, String> {
    let path = settings_path();
    if !path.exists() {
        return Ok(DesktopSettings::default());
    }

    let content = fs::read_to_string(&path).map_err(|error| error.to_string())?;
    serde_json::from_str(&content).map_err(|error| error.to_string())
}

fn write_settings(settings: &DesktopSettings) -> Result<(), String> {
    let path = settings_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }

    let content = serde_json::to_string_pretty(settings)
        .map_err(|error| format!("serialize failed: {error}"))?;
    fs::write(path, content).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn desktop_bootstrap() -> Result<DesktopBootstrapStatus, String> {
    Ok(compatibility::bootstrap(env!("CARGO_PKG_VERSION")).await)
}

#[tauri::command]
pub async fn system_version() -> Result<DaemonVersionInfo, String> {
    let value = call_daemon(Method::SystemVersion, None).await?;
    serde_json::from_value(value).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn system_check_dependencies() -> Result<Value, String> {
    call_daemon(Method::SystemCheckDependencies, None).await
}

#[tauri::command]
pub async fn board_list_companies() -> Result<Value, String> {
    let value = call_daemon(Method::CompanyList, None).await?;
    Ok(extract_field(value, "companies"))
}

#[tauri::command]
pub async fn board_create_company(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::CompanyCreate, Some(params)).await?;
    Ok(extract_field(value, "company"))
}

#[tauri::command]
pub async fn board_update_company(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::CompanyUpdate, Some(params)).await?;
    Ok(extract_field(value, "company"))
}

#[tauri::command]
pub async fn board_update_agent(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::AgentUpdate, Some(params)).await?;
    Ok(extract_field(value, "agent"))
}

#[tauri::command]
pub async fn board_company_snapshot(company_id: String) -> Result<Value, String> {
    let company_params = json!({ "company_id": company_id });
    let company_request = call_daemon(Method::CompanyGet, Some(company_params.clone()));
    let agents_request = call_daemon(Method::AgentList, Some(company_params.clone()));
    let goals_request = call_daemon(Method::GoalList, Some(company_params.clone()));
    let projects_request = call_daemon(Method::ProjectList, Some(company_params.clone()));
    let issues_request = call_daemon(Method::IssueList, Some(company_params.clone()));
    let approvals_request = call_daemon(Method::ApprovalList, Some(company_params.clone()));
    let workspaces_request = call_daemon(Method::WorkspaceList, Some(company_params));

    let (company, agents, goals, projects, issues, approvals, workspaces) = tokio::try_join!(
        company_request,
        agents_request,
        goals_request,
        projects_request,
        issues_request,
        approvals_request,
        workspaces_request
    )?;

    Ok(json!({
        "company": extract_field(company, "company"),
        "agents": extract_field(agents, "agents"),
        "goals": extract_field(goals, "goals"),
        "projects": extract_field(projects, "projects"),
        "issues": extract_field(issues, "issues"),
        "approvals": extract_field(approvals, "approvals"),
        "workspaces": extract_field(workspaces, "workspaces"),
    }))
}

#[tauri::command]
pub async fn board_create_project(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::ProjectCreate, Some(params)).await?;
    Ok(extract_field(value, "project"))
}

#[tauri::command]
pub async fn board_delete_project(project_id: String) -> Result<Value, String> {
    let value = call_daemon(Method::ProjectDelete, Some(json!({ "project_id": project_id }))).await?;
    Ok(extract_field(value, "project"))
}

#[tauri::command]
pub async fn board_create_issue(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::IssueCreate, Some(params)).await?;
    Ok(extract_field(value, "issue"))
}

#[tauri::command]
pub async fn board_get_issue(issue_id: String) -> Result<Value, String> {
    let value = call_daemon(Method::IssueGet, Some(json!({ "issue_id": issue_id }))).await?;
    Ok(extract_field(value, "issue"))
}

#[tauri::command]
pub async fn board_update_issue(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::IssueUpdate, Some(params)).await?;
    Ok(extract_field(value, "issue"))
}

#[tauri::command]
pub async fn board_list_issue_comments(issue_id: String) -> Result<Value, String> {
    let value = call_daemon(
        Method::IssueCommentList,
        Some(json!({ "issue_id": issue_id })),
    )
    .await?;
    Ok(extract_field(value, "comments"))
}

#[tauri::command]
pub async fn board_add_issue_comment(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::IssueCommentAdd, Some(params)).await?;
    Ok(extract_field(value, "comment"))
}

#[tauri::command]
pub async fn board_checkout_issue(issue_id: String) -> Result<Value, String> {
    let value = call_daemon(Method::IssueCheckout, Some(json!({ "issue_id": issue_id }))).await?;
    Ok(extract_field(value, "workspace"))
}

#[tauri::command]
pub async fn board_approve_approval(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::ApprovalApprove, Some(params)).await?;
    Ok(extract_field(value, "approval"))
}

#[tauri::command]
pub async fn board_list_agent_runs(agent_id: String, limit: Option<u32>) -> Result<Value, String> {
    let value = call_daemon(
        Method::AgentRunList,
        Some(json!({
            "agent_id": agent_id,
            "limit": limit,
        })),
    )
    .await?;
    Ok(extract_field(value, "runs"))
}

#[tauri::command]
pub async fn board_get_agent_run(run_id: String) -> Result<Value, String> {
    let value = call_daemon(Method::AgentRunGet, Some(json!({ "run_id": run_id }))).await?;
    Ok(extract_field(value, "run"))
}

#[tauri::command]
pub async fn board_list_agent_run_events(
    run_id: String,
    after_seq: Option<i64>,
    limit: Option<u32>,
) -> Result<Value, String> {
    let value = call_daemon(
        Method::AgentRunEvents,
        Some(json!({
            "run_id": run_id,
            "after_seq": after_seq,
            "limit": limit,
        })),
    )
    .await?;
    Ok(extract_field(value, "events"))
}

#[tauri::command]
pub async fn board_read_agent_run_log(
    run_id: String,
    offset: Option<u64>,
    limit_bytes: Option<u64>,
) -> Result<Value, String> {
    call_daemon(
        Method::AgentRunLog,
        Some(json!({
            "run_id": run_id,
            "offset": offset.unwrap_or(0),
            "limit_bytes": limit_bytes.unwrap_or(16_384),
        })),
    )
    .await
}

#[tauri::command]
pub async fn board_cancel_agent_run(run_id: String) -> Result<Value, String> {
    let value = call_daemon(Method::AgentRunCancel, Some(json!({ "run_id": run_id }))).await?;
    Ok(extract_field(value, "run"))
}

#[tauri::command]
pub async fn board_retry_agent_run(run_id: String) -> Result<Value, String> {
    let value = call_daemon(Method::AgentRunRetry, Some(json!({ "run_id": run_id }))).await?;
    Ok(extract_field(value, "run"))
}

#[tauri::command]
pub async fn board_resume_agent_run(run_id: String) -> Result<Value, String> {
    let value = call_daemon(Method::AgentRunResume, Some(json!({ "run_id": run_id }))).await?;
    Ok(extract_field(value, "run"))
}

#[tauri::command]
pub async fn repository_list() -> Result<Value, String> {
    let value = call_daemon(Method::RepositoryList, None).await?;
    Ok(extract_field(value, "repositories"))
}

#[tauri::command]
pub async fn repository_add(
    path: String,
    name: Option<String>,
    is_git_repository: Option<bool>,
) -> Result<Value, String> {
    let params = json!({
        "path": path,
        "name": name.unwrap_or_else(|| derive_repository_name(&path)),
        "is_git_repository": is_git_repository.unwrap_or(true),
    });
    call_daemon(Method::RepositoryAdd, Some(params)).await
}

#[tauri::command]
pub async fn repository_remove(id: String) -> Result<Value, String> {
    call_daemon(Method::RepositoryRemove, Some(json!({ "id": id }))).await
}

#[tauri::command]
pub async fn repository_get_settings(repository_id: String) -> Result<Value, String> {
    call_daemon(
        Method::RepositoryGetSettings,
        Some(json!({ "repository_id": repository_id })),
    )
    .await
}

#[tauri::command]
pub async fn repository_update_settings(params: Value) -> Result<Value, String> {
    call_daemon(Method::RepositoryUpdateSettings, Some(params)).await
}

#[tauri::command]
pub async fn repository_list_files(
    session_id: String,
    relative_path: Option<String>,
    include_hidden: Option<bool>,
) -> Result<Value, String> {
    let value = call_daemon(
        Method::RepositoryListFiles,
        Some(json!({
            "session_id": session_id,
            "relative_path": relative_path.unwrap_or_default(),
            "include_hidden": include_hidden.unwrap_or(false),
        })),
    )
    .await?;

    Ok(extract_field(value, "entries"))
}

#[tauri::command]
pub async fn repository_read_file(
    session_id: String,
    relative_path: String,
    max_bytes: Option<u64>,
) -> Result<Value, String> {
    call_daemon(
        Method::RepositoryReadFile,
        Some(json!({
            "session_id": session_id,
            "relative_path": relative_path,
            "max_bytes": max_bytes.unwrap_or(4 * 1024 * 1024),
        })),
    )
    .await
}

#[tauri::command]
pub async fn repository_write_file(
    session_id: String,
    relative_path: String,
    content: String,
    expected_revision: Option<Value>,
    force: Option<bool>,
) -> Result<Value, String> {
    let mut params = json!({
        "session_id": session_id,
        "relative_path": relative_path,
        "content": content,
        "force": force.unwrap_or(false),
    });

    if let Some(expected_revision) = expected_revision {
        params["expected_revision"] = expected_revision;
    }

    call_daemon(Method::RepositoryWriteFile, Some(params)).await
}

#[tauri::command]
pub async fn repository_replace_file_range(
    session_id: String,
    relative_path: String,
    start_line: usize,
    end_line_exclusive: usize,
    replacement: String,
    expected_revision: Option<Value>,
    force: Option<bool>,
) -> Result<Value, String> {
    let mut params = json!({
        "session_id": session_id,
        "relative_path": relative_path,
        "start_line": start_line,
        "end_line_exclusive": end_line_exclusive,
        "replacement": replacement,
        "force": force.unwrap_or(false),
    });

    if let Some(expected_revision) = expected_revision {
        params["expected_revision"] = expected_revision;
    }

    call_daemon(Method::RepositoryReplaceFileRange, Some(params)).await
}

#[tauri::command]
pub async fn session_list(repository_id: String) -> Result<Value, String> {
    let value = call_daemon(
        Method::SessionList,
        Some(json!({ "repository_id": repository_id })),
    )
    .await?;
    Ok(extract_field(value, "sessions"))
}

#[tauri::command]
pub async fn session_create(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::SessionCreate, Some(params)).await?;
    Ok(extract_field(value, "session"))
}

#[tauri::command]
pub async fn session_get(id: String) -> Result<Value, String> {
    let value = call_daemon(Method::SessionGet, Some(json!({ "id": id }))).await?;
    Ok(extract_field(value, "session"))
}

#[tauri::command]
pub async fn session_update(params: Value) -> Result<Value, String> {
    let value = call_daemon(Method::SessionUpdate, Some(params)).await?;
    Ok(extract_field(value, "session"))
}

#[tauri::command]
pub async fn message_list(session_id: String) -> Result<Value, String> {
    let value = call_daemon(
        Method::MessageList,
        Some(json!({ "session_id": session_id })),
    )
    .await?;
    Ok(extract_field(value, "messages"))
}

#[tauri::command]
pub async fn claude_send(
    session_id: String,
    content: String,
    permission_mode: Option<String>,
) -> Result<Value, String> {
    let mut params = json!({
        "session_id": session_id,
        "content": content,
    });

    if let Some(permission_mode) = permission_mode {
        params["permission_mode"] = json!(permission_mode);
    }

    call_daemon(Method::ClaudeSend, Some(params)).await
}

#[tauri::command]
pub async fn claude_status(session_id: String) -> Result<Value, String> {
    call_daemon(
        Method::ClaudeStatus,
        Some(json!({ "session_id": session_id })),
    )
    .await
}

#[tauri::command]
pub async fn claude_stop(session_id: String) -> Result<Value, String> {
    call_daemon(
        Method::ClaudeStop,
        Some(json!({ "session_id": session_id })),
    )
    .await
}

#[tauri::command]
pub async fn git_status(
    session_id: Option<String>,
    repository_id: Option<String>,
    path: Option<String>,
) -> Result<Value, String> {
    let mut params = json!({});
    if let Some(session_id) = session_id {
        params["session_id"] = json!(session_id);
    }
    if let Some(repository_id) = repository_id {
        params["repository_id"] = json!(repository_id);
    }
    if let Some(path) = path {
        params["path"] = json!(path);
    }
    call_daemon(Method::GitStatus, Some(params)).await
}

#[tauri::command]
pub async fn git_diff_file(
    file_path: String,
    session_id: Option<String>,
    repository_id: Option<String>,
    path: Option<String>,
    max_lines: Option<usize>,
) -> Result<Value, String> {
    let mut params = json!({
        "file_path": file_path,
    });
    if let Some(session_id) = session_id {
        params["session_id"] = json!(session_id);
    }
    if let Some(repository_id) = repository_id {
        params["repository_id"] = json!(repository_id);
    }
    if let Some(path) = path {
        params["path"] = json!(path);
    }
    if let Some(max_lines) = max_lines {
        params["max_lines"] = json!(max_lines);
    }
    call_daemon(Method::GitDiffFile, Some(params)).await
}

#[tauri::command]
pub async fn git_log(
    session_id: Option<String>,
    repository_id: Option<String>,
    path: Option<String>,
) -> Result<Value, String> {
    let mut params = json!({});
    if let Some(session_id) = session_id {
        params["session_id"] = json!(session_id);
    }
    if let Some(repository_id) = repository_id {
        params["repository_id"] = json!(repository_id);
    }
    if let Some(path) = path {
        params["path"] = json!(path);
    }
    call_daemon(Method::GitLog, Some(params)).await
}

#[tauri::command]
pub async fn git_branches(
    session_id: Option<String>,
    repository_id: Option<String>,
    path: Option<String>,
) -> Result<Value, String> {
    let mut params = json!({});
    if let Some(session_id) = session_id {
        params["session_id"] = json!(session_id);
    }
    if let Some(repository_id) = repository_id {
        params["repository_id"] = json!(repository_id);
    }
    if let Some(path) = path {
        params["path"] = json!(path);
    }
    call_daemon(Method::GitBranches, Some(params)).await
}

#[tauri::command]
pub async fn git_stage(paths: Vec<String>, session_id: Option<String>) -> Result<Value, String> {
    call_daemon(
        Method::GitStage,
        Some(json!({
            "session_id": session_id,
            "paths": paths,
        })),
    )
    .await
}

#[tauri::command]
pub async fn git_unstage(paths: Vec<String>, session_id: Option<String>) -> Result<Value, String> {
    call_daemon(
        Method::GitUnstage,
        Some(json!({
            "session_id": session_id,
            "paths": paths,
        })),
    )
    .await
}

#[tauri::command]
pub async fn git_discard(paths: Vec<String>, session_id: Option<String>) -> Result<Value, String> {
    call_daemon(
        Method::GitDiscard,
        Some(json!({
            "session_id": session_id,
            "paths": paths,
        })),
    )
    .await
}

#[tauri::command]
pub async fn git_commit(params: Value) -> Result<Value, String> {
    call_daemon(Method::GitCommitChanges, Some(params)).await
}

#[tauri::command]
pub async fn git_push(params: Value) -> Result<Value, String> {
    call_daemon(Method::GitPush, Some(params)).await
}

#[tauri::command]
pub async fn terminal_run(
    session_id: String,
    command: String,
    working_dir: Option<String>,
) -> Result<Value, String> {
    let mut params = json!({
        "session_id": session_id,
        "command": command,
    });
    if let Some(working_dir) = working_dir {
        params["working_dir"] = json!(working_dir);
    }
    call_daemon(Method::TerminalRun, Some(params)).await
}

#[tauri::command]
pub async fn terminal_status(session_id: String) -> Result<Value, String> {
    call_daemon(
        Method::TerminalStatus,
        Some(json!({ "session_id": session_id })),
    )
    .await
}

#[tauri::command]
pub async fn terminal_stop(session_id: String) -> Result<Value, String> {
    call_daemon(
        Method::TerminalStop,
        Some(json!({ "session_id": session_id })),
    )
    .await
}

#[tauri::command]
pub async fn session_subscribe(
    app: AppHandle,
    state: State<'_, DesktopState>,
    session_id: String,
) -> Result<(), String> {
    {
        let subscriptions = state
            .subscriptions
            .lock()
            .map_err(|_| "subscription state lock poisoned".to_string())?;
        if subscriptions.contains_key(&session_id) {
            return Ok(());
        }
    }

    let session_id_for_task = session_id.clone();
    let runtime_paths = compatibility::resolve_runtime_paths();
    let socket_path = runtime_paths.socket_path.display().to_string();
    let handle = tauri::async_runtime::spawn(async move {
        let client = IpcClient::new(&socket_path);
        match client.subscribe(&session_id_for_task).await {
            Ok(mut subscription) => {
                while let Some(event) = subscription.recv().await {
                    let payload = SessionStreamPayload {
                        session_id: session_id_for_task.clone(),
                        event: serde_json::to_value(&event).unwrap_or_else(|_| json!({})),
                    };
                    let _ = app.emit("daemon-session-event", payload);
                }
            }
            Err(error) => {
                let _ = app.emit(
                    "daemon-session-stream-error",
                    json!({
                        "session_id": session_id_for_task,
                        "message": error.to_string(),
                    }),
                );
            }
        }
    });

    let mut subscriptions = state
        .subscriptions
        .lock()
        .map_err(|_| "subscription state lock poisoned".to_string())?;
    subscriptions.insert(session_id, handle);
    Ok(())
}

#[tauri::command]
pub async fn session_unsubscribe(
    state: State<'_, DesktopState>,
    session_id: String,
) -> Result<(), String> {
    let mut subscriptions = state
        .subscriptions
        .lock()
        .map_err(|_| "subscription state lock poisoned".to_string())?;
    if let Some(handle) = subscriptions.remove(&session_id) {
        handle.abort();
    }
    Ok(())
}

#[tauri::command]
pub async fn settings_get() -> Result<DesktopSettings, String> {
    read_settings()
}

#[tauri::command]
pub async fn settings_update(settings: DesktopSettings) -> Result<DesktopSettings, String> {
    write_settings(&settings)?;
    Ok(settings)
}

#[tauri::command]
pub async fn desktop_pick_repository_directory() -> Result<Option<String>, String> {
    Ok(rfd::AsyncFileDialog::new()
        .pick_folder()
        .await
        .map(|handle| handle.path().display().to_string()))
}

#[tauri::command]
pub async fn desktop_pick_file() -> Result<Option<String>, String> {
    Ok(rfd::AsyncFileDialog::new()
        .pick_file()
        .await
        .map(|handle| handle.path().display().to_string()))
}

#[tauri::command]
pub async fn desktop_reveal_in_finder(path: String) -> Result<(), String> {
    Command::new("/usr/bin/open")
        .args(["-R", &path])
        .status()
        .map_err(|error| error.to_string())
        .and_then(|status| {
            if status.success() {
                Ok(())
            } else {
                Err(format!("open -R exited with status {status}"))
            }
        })
}

#[tauri::command]
pub async fn desktop_open_external(url: String) -> Result<(), String> {
    let parsed = Url::parse(&url).map_err(|error| error.to_string())?;
    Command::new("/usr/bin/open")
        .arg(parsed.as_str())
        .status()
        .map_err(|error| error.to_string())
        .and_then(|status| {
            if status.success() {
                Ok(())
            } else {
                Err(format!("open exited with status {status}"))
            }
        })
}
