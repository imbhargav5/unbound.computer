use crate::compatibility::{self, DesktopBootstrapStatus};
use crate::observability::{command_span, in_command_span, spawn_in_current_span};
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
use tracing::Instrument;
use url::Url;

#[derive(Default)]
pub struct DesktopState {
    subscriptions: Mutex<HashMap<String, JoinHandle<()>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct SavedDashboardProjectViewSettings {
    pub id: String,
    pub name: Option<String>,
    pub group_by: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DashboardProjectViewSettings {
    pub group_by: Option<String>,
    pub saved_views: Option<Vec<SavedDashboardProjectViewSettings>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct BirdsEyeCanvasViewportSettings {
    pub x: f64,
    pub y: f64,
    pub zoom_index: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct BirdsEyeCanvasRepoRegionSettings {
    pub page: Option<i64>,
    pub x: f64,
    pub y: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct BirdsEyeCanvasWorktreeTileSettings {
    pub active_issue_id: Option<String>,
    pub issue_ids: Option<Vec<String>>,
    pub lru_issue_ids: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct BirdsEyeCanvasFocusTargetSettings {
    pub kind: String,
    pub issue_id: Option<String>,
    pub project_id: String,
    pub worktree_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct BirdsEyeCanvasCompanySettings {
    pub focused_target: Option<BirdsEyeCanvasFocusTargetSettings>,
    pub repo_regions: Option<HashMap<String, BirdsEyeCanvasRepoRegionSettings>>,
    pub viewport: Option<BirdsEyeCanvasViewportSettings>,
    pub worktree_tiles: Option<HashMap<String, BirdsEyeCanvasWorktreeTileSettings>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DesktopSettings {
    pub preferred_company_id: Option<String>,
    pub preferred_repository_id: Option<String>,
    pub preferred_space_id: Option<String>,
    pub preferred_view: Option<String>,
    pub show_raw_message_json: bool,
    pub last_repository_path: Option<String>,
    pub onboarding_version: Option<u32>,
    pub theme_mode: Option<String>,
    pub font_size_preset: Option<String>,
    pub dashboard_project_views: Option<HashMap<String, DashboardProjectViewSettings>>,
    pub birds_eye_canvas: Option<HashMap<String, BirdsEyeCanvasCompanySettings>>,
}

impl Default for DesktopSettings {
    fn default() -> Self {
        Self {
            preferred_company_id: None,
            preferred_repository_id: None,
            preferred_space_id: None,
            preferred_view: Some("dashboard".to_string()),
            show_raw_message_json: false,
            last_repository_path: None,
            onboarding_version: Some(0),
            theme_mode: Some("dark".to_string()),
            font_size_preset: Some("medium".to_string()),
            dashboard_project_views: Some(HashMap::new()),
            birds_eye_canvas: Some(HashMap::new()),
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

fn method_operation_name(method: &Method) -> String {
    serde_json::to_value(method)
        .ok()
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .unwrap_or_else(|| format!("{method:?}").to_ascii_lowercase())
}

fn session_id_from_params(params: Option<&Value>) -> Option<String> {
    params.and_then(|value| {
        value
            .get("session_id")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned)
    })
}

async fn call_daemon(method: Method, params: Option<Value>) -> Result<Value, String> {
    let operation = method_operation_name(&method);
    let session_id = session_id_from_params(params.as_ref());

    in_command_span(operation.as_str(), session_id.as_deref(), async move {
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
    })
    .await
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

fn normalize_optional_id(value: Option<String>) -> Option<String> {
    value.map(|value| value.trim().to_string()).filter(|value| !value.is_empty())
}

fn preferred_space_id_from_settings() -> Option<String> {
    read_settings()
        .ok()
        .and_then(|settings| normalize_optional_id(settings.preferred_space_id))
}

fn inject_preferred_space_id(mut params: Value) -> Value {
    let preferred_space_id = preferred_space_id_from_settings();
    let Some(object) = params.as_object_mut() else {
        return params;
    };

    let existing_space_id = object
        .get("space_id")
        .and_then(Value::as_str)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());

    if let Some(existing_space_id) = existing_space_id {
        object.insert("space_id".to_string(), json!(existing_space_id));
    } else if let Some(preferred_space_id) = preferred_space_id {
        object.insert("space_id".to_string(), json!(preferred_space_id));
    }

    params
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
    in_command_span("desktop.bootstrap", None, async {
        Ok(compatibility::bootstrap(env!("CARGO_PKG_VERSION")).await)
    })
    .await
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
pub async fn space_get_current() -> Result<Value, String> {
    call_daemon(Method::SpaceGetCurrent, None).await
}

#[tauri::command]
pub async fn space_update_current_machine_name(name: String) -> Result<Value, String> {
    call_daemon(
        Method::SpaceUpdateCurrentMachineName,
        Some(json!({ "name": name })),
    )
    .await
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
    let mut params = json!({
        "path": path,
        "name": name.unwrap_or_else(|| derive_repository_name(&path)),
        "is_git_repository": is_git_repository.unwrap_or(true),
    });
    if let Some(space_id) = preferred_space_id_from_settings() {
        params["space_id"] = json!(space_id);
    }
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
    let params = inject_preferred_space_id(params);
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
pub async fn agent_send(
    session_id: String,
    content: String,
    provider: Option<String>,
    permission_mode: Option<String>,
) -> Result<Value, String> {
    let mut params = json!({
        "session_id": session_id,
        "content": content,
    });

    if let Some(provider) = provider {
        params["provider"] = json!(provider);
    }
    if let Some(permission_mode) = permission_mode {
        params["permission_mode"] = json!(permission_mode);
    }

    call_daemon(Method::AgentSend, Some(params)).await
}

#[tauri::command]
pub async fn agent_status(session_id: String) -> Result<Value, String> {
    call_daemon(
        Method::AgentStatus,
        Some(json!({ "session_id": session_id })),
    )
    .await
}

#[tauri::command]
pub async fn agent_stop(session_id: String) -> Result<Value, String> {
    call_daemon(Method::AgentStop, Some(json!({ "session_id": session_id }))).await
}

#[tauri::command]
pub async fn claude_send(
    session_id: String,
    content: String,
    permission_mode: Option<String>,
) -> Result<Value, String> {
    call_daemon(
        Method::ClaudeSend,
        Some(json!({
            "session_id": session_id,
            "content": content,
            "permission_mode": permission_mode,
        })),
    )
    .await
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
pub async fn git_worktrees(
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
    let value = call_daemon(Method::GitWorktrees, Some(params)).await?;
    Ok(extract_field(value, "worktrees"))
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
    let session_id_for_span = session_id.clone();
    in_command_span(
        "session.subscribe",
        Some(session_id_for_span.as_str()),
        async move {
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
            let stream_span = command_span(
                "session.subscribe.stream",
                Some(session_id_for_task.as_str()),
            );
            let handle = spawn_in_current_span(async move {
                async move {
                    let client = IpcClient::new(&socket_path);
                    match client.subscribe(&session_id_for_task).await {
                        Ok(mut subscription) => {
                            tracing::info!(
                                session_id = %session_id_for_task,
                                "desktop session subscription established"
                            );
                            while let Some(event) = subscription.recv().await {
                                let payload = SessionStreamPayload {
                                    session_id: session_id_for_task.clone(),
                                    event: serde_json::to_value(&event)
                                        .unwrap_or_else(|_| json!({})),
                                };
                                let _ = app.emit("daemon-session-event", payload);
                            }
                            tracing::info!(
                                session_id = %session_id_for_task,
                                "desktop session subscription closed"
                            );
                        }
                        Err(error) => {
                            tracing::error!(
                                error = %error,
                                session_id = %session_id_for_task,
                                "desktop session subscription failed"
                            );
                            let _ = app.emit(
                                "daemon-session-stream-error",
                                json!({
                                    "session_id": session_id_for_task,
                                    "message": error.to_string(),
                                }),
                            );
                        }
                    }
                }
                .instrument(stream_span)
                .await
            });

            let mut subscriptions = state
                .subscriptions
                .lock()
                .map_err(|_| "subscription state lock poisoned".to_string())?;
            subscriptions.insert(session_id, handle);
            Ok(())
        },
    )
    .await
}

#[tauri::command]
pub async fn session_unsubscribe(
    state: State<'_, DesktopState>,
    session_id: String,
) -> Result<(), String> {
    let session_id_for_span = session_id.clone();
    in_command_span(
        "session.unsubscribe",
        Some(session_id_for_span.as_str()),
        async move {
            let mut subscriptions = state
                .subscriptions
                .lock()
                .map_err(|_| "subscription state lock poisoned".to_string())?;
            if let Some(handle) = subscriptions.remove(&session_id) {
                handle.abort();
            }
            Ok(())
        },
    )
    .await
}

#[tauri::command]
pub async fn settings_get() -> Result<DesktopSettings, String> {
    in_command_span("settings.get", None, async { read_settings() }).await
}

#[tauri::command]
pub async fn settings_update(settings: DesktopSettings) -> Result<DesktopSettings, String> {
    in_command_span("settings.update", None, async move {
        write_settings(&settings)?;
        Ok(settings)
    })
    .await
}

#[tauri::command]
pub async fn desktop_pick_repository_directory() -> Result<Option<String>, String> {
    in_command_span("desktop.pick_repository_directory", None, async {
        Ok(rfd::AsyncFileDialog::new()
            .pick_folder()
            .await
            .map(|handle| handle.path().display().to_string()))
    })
    .await
}

#[tauri::command]
pub async fn desktop_pick_file() -> Result<Option<String>, String> {
    in_command_span("desktop.pick_file", None, async {
        Ok(rfd::AsyncFileDialog::new()
            .pick_file()
            .await
            .map(|handle| handle.path().display().to_string()))
    })
    .await
}

#[tauri::command]
pub async fn desktop_reveal_in_finder(path: String) -> Result<(), String> {
    in_command_span("desktop.reveal_in_finder", None, async move {
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
    })
    .await
}

#[tauri::command]
pub async fn desktop_open_external(url: String) -> Result<(), String> {
    in_command_span("desktop.open_external", None, async move {
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
    })
    .await
}
