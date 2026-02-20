//! Session handlers.

use crate::app::DaemonState;
use crate::utils::repository_config::{
    default_worktree_root_dir_for_repo, load_repository_config, SetupHookStageConfig,
};
use armin::{NewSession, RepositoryId, SessionId, SessionReader, SessionUpdate, SessionWriter};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use daemon_storage::SecretsManager;
use piccolo::{create_worktree_with_options, remove_worktree};
use std::path::Path;
use std::process::Stdio;
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::time::{timeout, Duration};
use tracing::{debug, warn};

const MAX_HOOK_STDERR_CHARS: usize = 1200;

#[derive(Debug, Clone)]
pub struct SessionCreateCoreError {
    code: String,
    message: String,
    data: Option<serde_json::Value>,
}

impl SessionCreateCoreError {
    fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            data: None,
        }
    }

    fn with_data(
        code: impl Into<String>,
        message: impl Into<String>,
        data: serde_json::Value,
    ) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            data: Some(data),
        }
    }

    pub fn into_response_parts(self) -> (String, String, Option<serde_json::Value>) {
        (self.code, self.message, self.data)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HookStage {
    PreCreate,
    PostCreate,
}

impl HookStage {
    fn as_str(self) -> &'static str {
        match self {
            Self::PreCreate => "pre_create",
            Self::PostCreate => "post_create",
        }
    }
}

fn normalize_optional_string(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(String::from)
}

fn is_legacy_worktree_root(root_dir: &str) -> bool {
    let trimmed = root_dir.trim();
    if trimmed.is_empty() {
        return false;
    }

    Path::new(trimmed)
        .components()
        .any(|component| component.as_os_str().to_string_lossy() == ".unbound-worktrees")
}

fn validate_worktree_name(name: &str) -> Result<(), String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err("worktree_name must not be empty or whitespace".to_string());
    }
    if trimmed != name {
        return Err("worktree_name must not have leading or trailing whitespace".to_string());
    }
    if trimmed.contains('/') || trimmed.contains('\\') {
        return Err("worktree_name must not contain path separators".to_string());
    }
    if trimmed == "." {
        return Err("worktree_name must not be '.'".to_string());
    }
    if trimmed.contains("..") {
        return Err("worktree_name must not contain '..'".to_string());
    }
    if !trimmed
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.')
    {
        return Err(
            "worktree_name may only contain ASCII letters, numbers, '.', '_', and '-'".to_string(),
        );
    }
    Ok(())
}

fn resolve_worktree_branch(params: &serde_json::Value) -> Option<String> {
    normalize_optional_string(params.get("worktree_branch").and_then(|v| v.as_str()))
        .or_else(|| normalize_optional_string(params.get("branch_name").and_then(|v| v.as_str())))
}

fn resolve_base_branch(
    request_base_branch: Option<String>,
    config_default_base_branch: Option<String>,
    repository_default_branch: Option<String>,
) -> Option<String> {
    request_base_branch
        .or(config_default_base_branch)
        .or(repository_default_branch)
}

fn truncate_for_error(text: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }

    let mut chars = text.chars();
    let truncated: String = chars.by_ref().take(max_chars).collect();
    if chars.next().is_some() {
        format!("{truncated}...")
    } else {
        truncated
    }
}

async fn run_setup_hook(
    stage: HookStage,
    hook: &SetupHookStageConfig,
    cwd: &Path,
) -> Result<(), SessionCreateCoreError> {
    let Some(command) = normalize_optional_string(hook.command.as_deref()) else {
        return Ok(());
    };

    let timeout_seconds = hook.timeout_seconds.max(1);
    let timeout_duration = Duration::from_secs(timeout_seconds);

    let mut process = Command::new("/bin/zsh");
    process
        .arg("-lc")
        .arg(&command)
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped());

    #[cfg(unix)]
    {
        // Put the hook in its own process group so timeout cleanup can terminate
        // both the shell and any spawned children.
        unsafe {
            process.pre_exec(|| {
                if libc::setpgid(0, 0) == -1 {
                    return Err(std::io::Error::last_os_error());
                }
                Ok(())
            });
        }
    }

    let mut child = process.spawn().map_err(|e| {
        SessionCreateCoreError::with_data(
            "setup_hook_failed",
            format!(
                "setup hook failed at stage {}: failed to execute command: {}",
                stage.as_str(),
                e
            ),
            serde_json::json!({
                "stage": stage.as_str(),
            }),
        )
    })?;

    let stderr_handle = child.stderr.take().map(|mut stderr| {
        tokio::spawn(async move {
            let mut buf = Vec::new();
            let _ = stderr.read_to_end(&mut buf).await;
            buf
        })
    });

    let output = match timeout(timeout_duration, child.wait()).await {
        Ok(result) => result.map_err(|e| {
            SessionCreateCoreError::with_data(
                "setup_hook_failed",
                format!(
                    "setup hook failed at stage {}: failed to execute command: {}",
                    stage.as_str(),
                    e
                ),
                serde_json::json!({
                    "stage": stage.as_str(),
                }),
            )
        })?,
        Err(_) => {
            let mut cleanup_error: Option<String> = None;

            #[cfg(unix)]
            {
                if let Some(raw_pid) = child.id() {
                    let rc = unsafe { libc::kill(-(raw_pid as i32), libc::SIGKILL) };
                    if rc == -1 {
                        let err = std::io::Error::last_os_error();
                        // Ignore "no such process" because the child may have exited
                        // naturally between timeout and kill.
                        if err.raw_os_error() != Some(libc::ESRCH) {
                            cleanup_error =
                                Some(format!("failed to kill hook process group: {}", err));
                        }
                    }
                }
            }

            #[cfg(not(unix))]
            {
                if let Err(e) = child.kill().await {
                    cleanup_error = Some(format!("failed to kill hook process: {}", e));
                }
            }

            if let Err(e) = child.wait().await {
                let msg = format!("failed to reap timed out hook process: {}", e);
                cleanup_error = match cleanup_error {
                    Some(existing) => Some(format!("{existing}; {msg}")),
                    None => Some(msg),
                };
            }

            if let Some(handle) = stderr_handle {
                let _ = handle.await;
            }

            let mut data = serde_json::json!({
                "stage": stage.as_str(),
                "timeout_seconds": timeout_seconds,
            });
            if let Some(cleanup_error) = cleanup_error {
                data["cleanup_error"] = serde_json::json!(cleanup_error);
            }

            return Err(SessionCreateCoreError::with_data(
                "setup_hook_failed",
                format!(
                    "setup hook timed out at stage {} after {}s",
                    stage.as_str(),
                    timeout_seconds
                ),
                data,
            ));
        }
    };

    let stderr = if let Some(handle) = stderr_handle {
        match handle.await {
            Ok(stderr_bytes) => String::from_utf8_lossy(&stderr_bytes).to_string(),
            Err(_) => String::new(),
        }
    } else {
        String::new()
    };

    if output.success() {
        return Ok(());
    }

    let stderr_trimmed = stderr.trim();
    let stderr_summary = truncate_for_error(stderr_trimmed, MAX_HOOK_STDERR_CHARS);
    let exit_code = output.code();
    let mut message = format!(
        "setup hook failed at stage {} with exit code {:?}",
        stage.as_str(),
        exit_code
    );

    if !stderr_summary.is_empty() {
        message.push_str(": ");
        message.push_str(&stderr_summary);
    }

    Err(SessionCreateCoreError::with_data(
        "setup_hook_failed",
        message,
        serde_json::json!({
            "stage": stage.as_str(),
            "exit_code": exit_code,
            "stderr": if stderr_summary.is_empty() {
                serde_json::Value::Null
            } else {
                serde_json::Value::String(stderr_summary)
            }
        }),
    ))
}

/// Register session handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_session_list(server, state.clone()).await;
    register_session_create(server, state.clone()).await;
    register_session_get(server, state.clone()).await;
    register_session_update(server, state.clone()).await;
    register_session_delete(server, state).await;
}

async fn register_session_list(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionList, move |req| {
            let armin = state.armin.clone();
            async move {
                let repo_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("repository_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_lowercase());

                let Some(repo_id) = repo_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "repository_id is required",
                    );
                };

                let repository_id = RepositoryId::from_string(&repo_id);
                let sessions = match armin.list_sessions(&repository_id) {
                    Ok(s) => s,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to list sessions: {}", e),
                        );
                    }
                };

                let session_data: Vec<serde_json::Value> = sessions
                    .iter()
                    .map(|s| {
                        serde_json::json!({
                            "id": s.id.as_str(),
                            "repository_id": s.repository_id.as_str(),
                            "title": s.title,
                            "claude_session_id": s.claude_session_id,
                            "status": s.status.as_str(),
                            "is_worktree": s.is_worktree,
                            "worktree_path": s.worktree_path,
                            "created_at": s.created_at.to_rfc3339(),
                            "last_accessed_at": s.last_accessed_at.to_rfc3339(),
                        })
                    })
                    .collect();
                Response::success(&req.id, serde_json::json!({ "sessions": session_data }))
            }
        })
        .await;
}

/// Core session creation logic shared by IPC and remote command paths.
/// Takes params as a serde_json::Value and returns the result or an error.
pub async fn create_session_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, SessionCreateCoreError> {
    let repository_id = params
        .get("repository_id")
        .and_then(|v| v.as_str())
        .map(|s| s.to_lowercase());

    let title = params
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("New session")
        .to_string();

    let is_worktree = params
        .get("is_worktree")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let worktree_name = params
        .get("worktree_name")
        .and_then(|v| v.as_str())
        .and_then(|s| normalize_optional_string(Some(s)));
    let requested_base_branch =
        normalize_optional_string(params.get("base_branch").and_then(|v| v.as_str()));
    let requested_worktree_branch = resolve_worktree_branch(params);

    let Some(repository_id) = repository_id else {
        return Err(SessionCreateCoreError::new(
            "invalid_params",
            "repository_id is required",
        ));
    };
    if let Some(name) = worktree_name.as_deref() {
        validate_worktree_name(name)
            .map_err(|msg| SessionCreateCoreError::new("invalid_params", msg))?;
    }

    let session_id = SessionId::new();
    let session_secret = SecretsManager::generate_session_secret();
    let mut worktree_cleanup_context: Option<(String, String)> = None;

    let worktree_path = if is_worktree {
        let repo_id = RepositoryId::from_string(&repository_id);
        let repo = match state.armin.get_repository(&repo_id) {
            Ok(Some(r)) => r,
            Ok(None) => {
                return Err(SessionCreateCoreError::new(
                    "not_found",
                    "Repository not found",
                ));
            }
            Err(e) => {
                return Err(SessionCreateCoreError::new(
                    "internal_error",
                    format!("Failed to get repository: {}", e),
                ));
            }
        };

        let repo_path = Path::new(&repo.path);
        let default_worktree_root_dir = default_worktree_root_dir_for_repo(repo.id.as_str());
        let repo_config =
            load_repository_config(repo_path, &default_worktree_root_dir).map_err(|e| {
                SessionCreateCoreError::new(
                    "internal_error",
                    format!("Failed to load repository config: {}", e),
                )
            })?;

        let effective_base_branch = resolve_base_branch(
            requested_base_branch,
            repo_config.worktree.default_base_branch.clone(),
            repo.default_branch.clone(),
        );
        let wt_name = worktree_name.as_deref().unwrap_or(session_id.as_str());
        let root_dir = if repo_config.worktree.root_dir.trim().is_empty() {
            default_worktree_root_dir.clone()
        } else {
            repo_config.worktree.root_dir.clone()
        };

        if is_legacy_worktree_root(&root_dir) {
            return Err(SessionCreateCoreError::with_data(
                "legacy_worktree_unsupported",
                "legacy worktree root '.unbound-worktrees' is not supported; use '~/.unbound/<repo_id>/worktrees'",
                serde_json::json!({
                    "configured_root_dir": root_dir,
                    "supported_root_dir": default_worktree_root_dir,
                }),
            ));
        }

        run_setup_hook(
            HookStage::PreCreate,
            &repo_config.setup_hooks.pre_create,
            repo_path,
        )
        .await?;

        let created_worktree_path = match create_worktree_with_options(
            repo_path,
            wt_name,
            Path::new(&root_dir),
            effective_base_branch.as_deref(),
            requested_worktree_branch.as_deref(),
        ) {
            Ok(path) => path,
            Err(e) => {
                return Err(SessionCreateCoreError::new(
                    "internal_error",
                    format!("Failed to create worktree: {}", e),
                ));
            }
        };

        if let Err(mut hook_error) = run_setup_hook(
            HookStage::PostCreate,
            &repo_config.setup_hooks.post_create,
            Path::new(&created_worktree_path),
        )
        .await
        {
            if let Err(cleanup_error) =
                remove_worktree(repo_path, Path::new(&created_worktree_path))
            {
                let cleanup_summary = truncate_for_error(&cleanup_error, MAX_HOOK_STDERR_CHARS);
                if let Some(data) = hook_error.data.as_mut() {
                    data["cleanup_error"] = serde_json::json!(cleanup_summary);
                } else {
                    hook_error.data = Some(serde_json::json!({
                        "cleanup_error": cleanup_summary,
                    }));
                }
                hook_error.message =
                    format!("{}; cleanup failed: {}", hook_error.message, cleanup_error);
            }
            return Err(hook_error);
        }

        worktree_cleanup_context = Some((repo.path.clone(), created_worktree_path.clone()));
        Some(created_worktree_path)
    } else {
        None
    };

    let new_session = NewSession {
        id: session_id.clone(),
        repository_id: RepositoryId::from_string(&repository_id),
        title,
        claude_session_id: None,
        is_worktree,
        worktree_path,
    };

    let created_session = match state.armin.create_session_with_metadata(new_session) {
        Ok(s) => s,
        Err(e) => {
            if let Some((repo_path, created_worktree_path)) = worktree_cleanup_context.take() {
                if let Err(cleanup_error) =
                    remove_worktree(Path::new(&repo_path), Path::new(&created_worktree_path))
                {
                    let cleanup_summary = truncate_for_error(&cleanup_error, MAX_HOOK_STDERR_CHARS);
                    return Err(SessionCreateCoreError::with_data(
                        "internal_error",
                        format!(
                            "Failed to create session: {}; cleanup failed: {}",
                            e, cleanup_error
                        ),
                        serde_json::json!({
                            "cleanup_error": cleanup_summary,
                            "worktree_path": created_worktree_path,
                        }),
                    ));
                }
            }

            return Err(SessionCreateCoreError::new(
                "internal_error",
                format!("Failed to create session: {}", e),
            ));
        }
    };

    // Source of truth: persist the session secret to Armin/SQLite.
    let db_key = match *state.db_encryption_key.lock().unwrap() {
        Some(db_key) => db_key,
        None => {
            return Err(rollback_session_creation_after_secret_failure(
                state,
                &created_session.id,
                &mut worktree_cleanup_context,
                "Database encryption key is unavailable; cannot persist session secret".to_string(),
            ));
        }
    };

    let nonce = daemon_database::generate_nonce();
    let encrypted_secret =
        match daemon_database::encrypt_content(&db_key, &nonce, session_secret.as_bytes()) {
            Ok(encrypted_secret) => encrypted_secret,
            Err(err) => {
                return Err(rollback_session_creation_after_secret_failure(
                    state,
                    &created_session.id,
                    &mut worktree_cleanup_context,
                    format!("Failed to encrypt session secret: {}", err),
                ));
            }
        };

    debug!(
        session_id = %created_session.id.as_str(),
        nonce_len = nonce.len(),
        encrypted_len = encrypted_secret.len(),
        plaintext_len = session_secret.len(),
        "Encrypted session secret, storing via Armin"
    );

    let new_secret = armin::NewSessionSecret {
        session_id: created_session.id.clone(),
        encrypted_secret,
        nonce: nonce.to_vec(),
    };
    if let Err(err) = state.armin.set_session_secret(new_secret) {
        return Err(rollback_session_creation_after_secret_failure(
            state,
            &created_session.id,
            &mut worktree_cleanup_context,
            format!("Failed to store session secret: {}", err),
        ));
    }

    debug!(
        session_id = %created_session.id.as_str(),
        "Stored session secret via Armin"
    );

    if let Ok(key) = SecretsManager::parse_session_secret(&session_secret) {
        state
            .session_secret_cache
            .insert(created_session.id.as_str(), key);
    }

    let supabase_future = {
        let session_sync = state.session_sync.clone();
        let session_id = created_session.id.as_str().to_string();
        let repository_id = created_session.repository_id.as_str().to_string();
        let session_secret = session_secret.clone();
        async move {
            if let Err(e) = session_sync
                .sync_new_session(&session_id, &repository_id, &session_secret)
                .await
            {
                warn!(
                    session_id = %session_id,
                    "Failed to sync session to Supabase: {}",
                    e
                );
            }
        }
    };

    supabase_future.await;

    let session_data = serde_json::json!({
        "id": created_session.id.as_str(),
        "repository_id": created_session.repository_id.as_str(),
        "title": created_session.title,
        "status": created_session.status.as_str(),
        "is_worktree": created_session.is_worktree,
        "worktree_path": created_session.worktree_path,
        "created_at": created_session.created_at.to_rfc3339(),
        "last_accessed_at": created_session.last_accessed_at.to_rfc3339(),
    });

    Ok(session_data)
}

fn rollback_session_creation_after_secret_failure(
    state: &DaemonState,
    session_id: &SessionId,
    worktree_cleanup_context: &mut Option<(String, String)>,
    reason: String,
) -> SessionCreateCoreError {
    state.session_secret_cache.remove(session_id.as_str());

    if let Err(delete_err) = state.armin.delete_session(session_id) {
        warn!(
            session_id = %session_id.as_str(),
            error = %delete_err,
            "Failed to rollback session after secret persistence failure"
        );
    }

    if let Some((repo_path, created_worktree_path)) = worktree_cleanup_context.take() {
        if let Err(cleanup_error) =
            remove_worktree(Path::new(&repo_path), Path::new(&created_worktree_path))
        {
            let cleanup_summary = truncate_for_error(&cleanup_error, MAX_HOOK_STDERR_CHARS);
            return SessionCreateCoreError::with_data(
                "internal_error",
                format!("{reason}; cleanup failed: {cleanup_error}"),
                serde_json::json!({
                    "cleanup_error": cleanup_summary,
                    "worktree_path": created_worktree_path,
                }),
            );
        }
    }

    SessionCreateCoreError::new("internal_error", reason)
}

async fn register_session_create(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionCreate, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match create_session_core(&state, &params).await {
                    Ok(data) => Response::success(&req.id, data),
                    Err(err) => {
                        let error_code = match err.code.as_str() {
                            "invalid_params" => error_codes::INVALID_PARAMS,
                            "not_found" => error_codes::NOT_FOUND,
                            _ => error_codes::INTERNAL_ERROR,
                        };
                        if let Some(data) = err.data {
                            Response::error_with_data(&req.id, error_code, &err.message, data)
                        } else {
                            Response::error(&req.id, error_code, &err.message)
                        }
                    }
                }
            }
        })
        .await;
}

async fn register_session_get(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionGet, move |req| {
            let armin = state.armin.clone();
            async move {
                let id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("id"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let Some(id) = id else {
                    return Response::error(&req.id, error_codes::INVALID_PARAMS, "id is required");
                };

                let session_id = SessionId::from_string(&id);
                match armin.get_session(&session_id) {
                    Ok(Some(s)) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "session": {
                                "id": s.id.as_str(),
                                "repository_id": s.repository_id.as_str(),
                                "title": s.title,
                                "status": s.status.as_str(),
                                "created_at": s.created_at.to_rfc3339(),
                                "last_accessed_at": s.last_accessed_at.to_rfc3339(),
                            }
                        }),
                    ),
                    Ok(None) => {
                        Response::error(&req.id, error_codes::NOT_FOUND, "Session not found")
                    }
                    Err(e) => Response::error(
                        &req.id,
                        error_codes::INTERNAL_ERROR,
                        &format!("Failed to get session: {}", e),
                    ),
                }
            }
        })
        .await;
}

async fn register_session_update(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionUpdate, move |req| {
            let armin = state.armin.clone();
            async move {
                let params = match req.params.as_ref() {
                    Some(params) => params,
                    None => {
                        return Response::error(
                            &req.id,
                            error_codes::INVALID_PARAMS,
                            "session_id and title are required",
                        );
                    }
                };

                let session_id = params
                    .get("session_id")
                    .or_else(|| params.get("id"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let title = normalize_optional_string(params.get("title").and_then(|v| v.as_str()));

                let Some(session_id) = session_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id is required",
                    );
                };

                let Some(title) = title else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "title must not be empty",
                    );
                };

                let session_id = SessionId::from_string(&session_id);
                let current = match armin.get_session(&session_id) {
                    Ok(Some(s)) => s,
                    Ok(None) => {
                        return Response::error(
                            &req.id,
                            error_codes::NOT_FOUND,
                            "Session not found",
                        );
                    }
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to get session: {}", e),
                        );
                    }
                };

                if current.title == title {
                    return Response::success(
                        &req.id,
                        serde_json::json!({
                            "session": {
                                "id": current.id.as_str(),
                                "repository_id": current.repository_id.as_str(),
                                "title": current.title,
                                "status": current.status.as_str(),
                                "created_at": current.created_at.to_rfc3339(),
                                "last_accessed_at": current.last_accessed_at.to_rfc3339(),
                            }
                        }),
                    );
                }

                let update = SessionUpdate {
                    title: Some(title),
                    last_accessed_at: Some(chrono::Utc::now()),
                    ..SessionUpdate::default()
                };

                let updated = match armin.update_session(&session_id, update) {
                    Ok(updated) => updated,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to update session: {}", e),
                        );
                    }
                };

                if !updated {
                    return Response::error(&req.id, error_codes::NOT_FOUND, "Session not found");
                }

                match armin.get_session(&session_id) {
                    Ok(Some(s)) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "session": {
                                "id": s.id.as_str(),
                                "repository_id": s.repository_id.as_str(),
                                "title": s.title,
                                "status": s.status.as_str(),
                                "created_at": s.created_at.to_rfc3339(),
                                "last_accessed_at": s.last_accessed_at.to_rfc3339(),
                            }
                        }),
                    ),
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Session not found"),
                    Err(e) => Response::error(
                        &req.id,
                        error_codes::INTERNAL_ERROR,
                        &format!("Failed to get session: {}", e),
                    ),
                }
            }
        })
        .await;
}

async fn register_session_delete(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionDelete, move |req| {
            let state = state.clone();
            async move {
                let id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("id"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let Some(id) = id else {
                    return Response::error(&req.id, error_codes::INVALID_PARAMS, "id is required");
                };

                // First, get the session to check if it's a worktree
                let session_id = SessionId::from_string(&id);
                let session = match state.armin.get_session(&session_id) {
                    Ok(Some(s)) => s,
                    Ok(None) => {
                        return Response::error(
                            &req.id,
                            error_codes::NOT_FOUND,
                            "Session not found",
                        );
                    }
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to get session: {}", e),
                        );
                    }
                };

                // If it's a worktree session, clean up the worktree
                if session.is_worktree {
                    if let Some(worktree_path) = &session.worktree_path {
                        // Get repository path for worktree cleanup
                        if let Ok(Some(repo)) = state.armin.get_repository(&session.repository_id) {
                            // Try to remove the worktree, but don't fail the deletion if this fails
                            if let Err(e) =
                                remove_worktree(Path::new(&repo.path), Path::new(worktree_path))
                            {
                                warn!(
                                    session_id = %session.id.as_str(),
                                    worktree_path = %worktree_path,
                                    "Failed to remove worktree: {}",
                                    e
                                );
                            } else {
                                debug!(
                                    session_id = %session.id.as_str(),
                                    worktree_path = %worktree_path,
                                    "Worktree removed successfully"
                                );
                            }
                        }
                    }
                }

                // Delete the session via Armin
                let deleted = match state.armin.delete_session(&session_id) {
                    Ok(d) => d,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to delete session: {}", e),
                        );
                    }
                };

                if deleted {
                    Response::success(&req.id, serde_json::json!({ "deleted": true }))
                } else {
                    Response::error(&req.id, error_codes::NOT_FOUND, "Session not found")
                }
            }
        })
        .await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn has_zsh() -> bool {
        Path::new("/bin/zsh").exists()
    }

    fn unique_temp_path(prefix: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        std::env::temp_dir().join(format!("{prefix}-{}-{nanos}", std::process::id()))
    }

    #[test]
    fn resolve_worktree_branch_prefers_new_param() {
        let params = serde_json::json!({
            "worktree_branch": "feature/new-branch",
            "branch_name": "legacy/branch-name"
        });

        assert_eq!(
            resolve_worktree_branch(&params),
            Some("feature/new-branch".to_string())
        );
    }

    #[test]
    fn resolve_worktree_branch_uses_legacy_alias_when_needed() {
        let params = serde_json::json!({
            "branch_name": "legacy/branch-name"
        });

        assert_eq!(
            resolve_worktree_branch(&params),
            Some("legacy/branch-name".to_string())
        );
    }

    #[test]
    fn resolve_base_branch_precedence() {
        let resolved = resolve_base_branch(
            Some("request-base".to_string()),
            Some("config-base".to_string()),
            Some("db-base".to_string()),
        );
        assert_eq!(resolved.as_deref(), Some("request-base"));

        let resolved = resolve_base_branch(
            None,
            Some("config-base".to_string()),
            Some("db-base".to_string()),
        );
        assert_eq!(resolved.as_deref(), Some("config-base"));

        let resolved = resolve_base_branch(None, None, Some("db-base".to_string()));
        assert_eq!(resolved.as_deref(), Some("db-base"));
    }

    #[test]
    fn legacy_worktree_root_detection() {
        assert!(is_legacy_worktree_root(".unbound-worktrees"));
        assert!(is_legacy_worktree_root("/tmp/repo/.unbound-worktrees"));
        assert!(is_legacy_worktree_root(
            "/tmp/repo/.unbound-worktrees/nested"
        ));
        assert!(is_legacy_worktree_root(
            "/tmp/repo/custom/.unbound-worktrees/root"
        ));
        assert!(!is_legacy_worktree_root(".unbound/worktrees"));
        assert!(!is_legacy_worktree_root("custom/worktrees"));
        assert!(!is_legacy_worktree_root("/tmp/repo/.unbound-worktrees-v2"));
    }

    #[test]
    fn validate_worktree_name_accepts_safe_values() {
        let valid = [
            "session-1",
            "unbound_123",
            "release.2026.02",
            "abcDEF-123_.name",
        ];
        for name in valid {
            assert!(
                validate_worktree_name(name).is_ok(),
                "expected valid worktree name: {}",
                name
            );
        }
    }

    #[test]
    fn validate_worktree_name_rejects_unsafe_values() {
        let invalid = [
            "",
            "   ",
            " session",
            "session ",
            "foo/bar",
            "foo\\bar",
            ".",
            "..",
            "a..b",
            "semi;colon",
            "emoji-\u{1F680}",
        ];
        for name in invalid {
            assert!(
                validate_worktree_name(name).is_err(),
                "expected invalid worktree name: {:?}",
                name
            );
        }
    }

    #[tokio::test]
    async fn run_setup_hook_non_zero_includes_stage_and_stderr() {
        if !has_zsh() {
            return;
        }

        let hook = SetupHookStageConfig {
            command: Some("echo hook failed >&2; exit 7".to_string()),
            timeout_seconds: 5,
        };
        let cwd = Path::new(env!("CARGO_MANIFEST_DIR"));
        let err = run_setup_hook(HookStage::PreCreate, &hook, cwd)
            .await
            .expect_err("hook should fail");

        assert_eq!(err.code, "setup_hook_failed");
        assert!(err.message.contains("pre_create"));
        let data = err.data.expect("expected structured hook error data");
        assert_eq!(data["stage"], "pre_create");
        assert!(data["stderr"]
            .as_str()
            .unwrap_or_default()
            .contains("hook failed"));
    }

    #[tokio::test]
    async fn run_setup_hook_timeout_includes_stage() {
        if !has_zsh() {
            return;
        }

        let hook = SetupHookStageConfig {
            command: Some("sleep 2".to_string()),
            timeout_seconds: 1,
        };
        let cwd = Path::new(env!("CARGO_MANIFEST_DIR"));
        let err = run_setup_hook(HookStage::PostCreate, &hook, cwd)
            .await
            .expect_err("hook should timeout");

        assert_eq!(err.code, "setup_hook_failed");
        assert!(err.message.contains("timed out"));
        let data = err.data.expect("expected structured hook timeout data");
        assert_eq!(data["stage"], "post_create");
        assert_eq!(data["timeout_seconds"], 1);
    }

    #[tokio::test]
    async fn run_setup_hook_timeout_kills_background_children() {
        if !has_zsh() {
            return;
        }

        let marker_file = unique_temp_path("hook-leak-check");
        let marker_path = marker_file
            .to_string_lossy()
            .replace('\\', "\\\\")
            .replace('"', "\\\"");

        let hook = SetupHookStageConfig {
            command: Some(format!(
                "nohup /bin/zsh -lc 'sleep 2; echo leaked > \"{}\"' >/dev/null 2>&1 & sleep 30",
                marker_path
            )),
            timeout_seconds: 1,
        };

        let cwd = Path::new(env!("CARGO_MANIFEST_DIR"));
        let err = run_setup_hook(HookStage::PreCreate, &hook, cwd)
            .await
            .expect_err("hook should timeout");

        assert_eq!(err.code, "setup_hook_failed");
        tokio::time::sleep(Duration::from_secs(3)).await;
        assert!(
            !marker_file.exists(),
            "timed-out hook leaked child process that wrote marker file"
        );
        let _ = fs::remove_file(marker_file);
    }
}
