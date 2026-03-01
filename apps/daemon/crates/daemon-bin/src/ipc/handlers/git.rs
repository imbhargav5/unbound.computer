//! Git handlers.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use git_ops::{
    commit, discard_changes, get_branches, get_file_diff, get_log, get_status, push, stage_files,
    unstage_files, GitOpsError,
};
use workspace_resolver::{
    resolve_repository_path, resolve_working_dir_from_str, ResolveError,
};

#[derive(Debug, Clone)]
pub struct GitCoreError {
    pub code: String,
    pub message: String,
}

/// Register git handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_git_status(server, state.clone()).await;
    register_git_diff_file(server, state.clone()).await;
    register_git_log(server, state.clone()).await;
    register_git_branches(server, state.clone()).await;
    register_git_stage(server, state.clone()).await;
    register_git_unstage(server, state.clone()).await;
    register_git_discard(server, state.clone()).await;
    register_git_commit(server, state.clone()).await;
    register_git_push(server, state).await;
}

pub async fn git_commit_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, GitCoreError> {
    let repo_path = resolve_git_repo_path(state, params)?;

    let message = params
        .get("message")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .ok_or_else(|| GitCoreError {
            code: "invalid_params".to_string(),
            message: "message is required".to_string(),
        })?;

    let author_name = params
        .get("author_name")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|v| !v.is_empty());

    let author_email = params
        .get("author_email")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|v| !v.is_empty());

    let stage_all = params
        .get("stage_all")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if stage_all {
        let all_paths = ["."];
        stage_files(std::path::Path::new(&repo_path), &all_paths).map_err(map_stage_error)?;
    }

    let result = commit(
        std::path::Path::new(&repo_path),
        message,
        author_name,
        author_email,
    )
    .map_err(map_git_ops_error)?;

    Ok(serde_json::json!({
        "oid": result.oid,
        "short_oid": result.short_oid,
        "summary": result.summary,
    }))
}

pub async fn git_push_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, GitCoreError> {
    let repo_path = resolve_git_repo_path(state, params)?;

    let remote = params
        .get("remote")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|v| !v.is_empty());

    let branch = params
        .get("branch")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|v| !v.is_empty());

    let result =
        push(std::path::Path::new(&repo_path), remote, branch).map_err(map_git_ops_error)?;

    Ok(serde_json::json!({
        "remote": result.remote,
        "branch": result.branch,
        "success": result.success,
    }))
}

async fn register_git_status(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitStatus, move |req| {
            let state = state.clone();
            async move {
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                // Get git status
                match get_status(std::path::Path::new(&repo_path)) {
                    Ok(status) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "files": status.files,
                            "branch": status.branch,
                            "is_clean": status.is_clean,
                        }),
                    ),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e),
                }
            }
        })
        .await;
}

async fn register_git_diff_file(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitDiffFile, move |req| {
            let state = state.clone();
            async move {
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                // Get file path
                let file_path = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("file_path"))
                    .and_then(|v| v.as_str());

                let Some(file_path) = file_path else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "file_path is required",
                    );
                };

                // Get max lines
                let max_lines = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("max_lines"))
                    .and_then(|v| v.as_u64())
                    .map(|n| n as usize);

                // Get diff
                match get_file_diff(std::path::Path::new(&repo_path), file_path, max_lines) {
                    Ok(diff) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "file_path": diff.file_path,
                            "diff": diff.diff,
                            "is_binary": diff.is_binary,
                            "is_truncated": diff.is_truncated,
                            "additions": diff.additions,
                            "deletions": diff.deletions,
                        }),
                    ),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e),
                }
            }
        })
        .await;
}

/// Helper to extract repository path from request params.
async fn extract_repo_path(
    state: &DaemonState,
    params: &Option<serde_json::Value>,
) -> Result<String, (i32, String)> {
    if let Some(session_id) = params
        .as_ref()
        .and_then(|p| p.get("session_id"))
        .and_then(|v| v.as_str())
    {
        if session_id.trim().is_empty() {
            return Err((
                error_codes::INVALID_PARAMS,
                "session_id must not be empty".to_string(),
            ));
        }
        return resolve_working_dir_from_str(&*state.armin, session_id)
            .map(|resolved| resolved.working_dir)
            .map_err(map_resolve_error);
    }

    if let Some(repo_id) = params
        .as_ref()
        .and_then(|p| p.get("repository_id"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_lowercase())
    {
        if repo_id.trim().is_empty() {
            return Err((
                error_codes::INVALID_PARAMS,
                "repository_id must not be empty".to_string(),
            ));
        }
        return resolve_repository_path(&*state.armin, &repo_id).map_err(map_resolve_error);
    }

    if let Some(path) = params
        .as_ref()
        .and_then(|p| p.get("path"))
        .and_then(|v| v.as_str())
    {
        if path.trim().is_empty() {
            return Err((
                error_codes::INVALID_PARAMS,
                "path must not be empty".to_string(),
            ));
        }
        return Ok(path.to_string());
    }

    Err((
        error_codes::INVALID_PARAMS,
        "one of session_id, repository_id, or path is required".to_string(),
    ))
}

fn map_resolve_error(err: ResolveError) -> (i32, String) {
    match err {
        ResolveError::SessionNotFound(message) | ResolveError::RepositoryNotFound(message) => {
            (error_codes::NOT_FOUND, message)
        }
        ResolveError::LegacyWorktreeUnsupported(message) => (error_codes::INTERNAL_ERROR, message),
        ResolveError::Armin(err) => (
            error_codes::INTERNAL_ERROR,
            format!("Failed to resolve repository path: {}", err),
        ),
    }
}

async fn register_git_log(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitLog, move |req| {
            let state = state.clone();
            async move {
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                let limit = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("limit"))
                    .and_then(|v| v.as_u64())
                    .map(|n| n as usize);

                let offset = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("offset"))
                    .and_then(|v| v.as_u64())
                    .map(|n| n as usize);

                let branch = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("branch"))
                    .and_then(|v| v.as_str());

                match get_log(std::path::Path::new(&repo_path), limit, offset, branch) {
                    Ok(log) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "commits": log.commits,
                            "has_more": log.has_more,
                            "total_count": log.total_count,
                        }),
                    ),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e),
                }
            }
        })
        .await;
}

async fn register_git_branches(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitBranches, move |req| {
            let state = state.clone();
            async move {
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                match get_branches(std::path::Path::new(&repo_path)) {
                    Ok(branches) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "local": branches.local,
                            "remote": branches.remote,
                            "current": branches.current,
                        }),
                    ),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e),
                }
            }
        })
        .await;
}

async fn register_git_stage(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitStage, move |req| {
            let state = state.clone();
            async move {
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                let paths: Vec<String> = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("paths"))
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default();

                if paths.is_empty() {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "paths array is required",
                    );
                }

                let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();

                match stage_files(std::path::Path::new(&repo_path), &path_refs) {
                    Ok(()) => Response::success(&req.id, serde_json::json!({ "success": true })),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e),
                }
            }
        })
        .await;
}

async fn register_git_unstage(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitUnstage, move |req| {
            let state = state.clone();
            async move {
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                let paths: Vec<String> = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("paths"))
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default();

                if paths.is_empty() {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "paths array is required",
                    );
                }

                let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();

                match unstage_files(std::path::Path::new(&repo_path), &path_refs) {
                    Ok(()) => Response::success(&req.id, serde_json::json!({ "success": true })),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e),
                }
            }
        })
        .await;
}

async fn register_git_discard(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitDiscard, move |req| {
            let state = state.clone();
            async move {
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                let paths: Vec<String> = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("paths"))
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default();

                if paths.is_empty() {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "paths array is required",
                    );
                }

                let path_refs: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();

                match discard_changes(std::path::Path::new(&repo_path), &path_refs) {
                    Ok(()) => Response::success(&req.id, serde_json::json!({ "success": true })),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e),
                }
            }
        })
        .await;
}

async fn register_git_commit(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitCommitChanges, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match git_commit_core(&state, &params).await {
                    Ok(result) => Response::success(&req.id, result),
                    Err(err) => git_core_error_response(&req.id, err),
                }
            }
        })
        .await;
}

async fn register_git_push(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitPush, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match git_push_core(&state, &params).await {
                    Ok(result) => Response::success(&req.id, result),
                    Err(err) => git_core_error_response(&req.id, err),
                }
            }
        })
        .await;
}

fn resolve_git_repo_path(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<String, GitCoreError> {
    if let Some(session_id) = params.get("session_id").and_then(|v| v.as_str()) {
        if session_id.trim().is_empty() {
            return Err(GitCoreError {
                code: "invalid_params".to_string(),
                message: "session_id must not be empty".to_string(),
            });
        }
        return resolve_working_dir_from_str(&*state.armin, session_id)
            .map(|resolved| resolved.working_dir)
            .map_err(map_resolve_error_core);
    }

    if let Some(repository_id) = params.get("repository_id").and_then(|v| v.as_str()) {
        if repository_id.trim().is_empty() {
            return Err(GitCoreError {
                code: "invalid_params".to_string(),
                message: "repository_id must not be empty".to_string(),
            });
        }
        return resolve_repository_path(&*state.armin, repository_id)
            .map_err(map_resolve_error_core);
    }

    if let Some(path) = params.get("path").and_then(|v| v.as_str()) {
        if path.trim().is_empty() {
            return Err(GitCoreError {
                code: "invalid_params".to_string(),
                message: "path must not be empty".to_string(),
            });
        }
        return Ok(path.to_string());
    }

    Err(GitCoreError {
        code: "invalid_params".to_string(),
        message: "one of session_id, repository_id, or path is required".to_string(),
    })
}

fn map_resolve_error_core(err: ResolveError) -> GitCoreError {
    match err {
        ResolveError::SessionNotFound(message) | ResolveError::RepositoryNotFound(message) => {
            GitCoreError {
                code: "not_found".to_string(),
                message,
            }
        }
        ResolveError::LegacyWorktreeUnsupported(message) => GitCoreError {
            code: "legacy_worktree_unsupported".to_string(),
            message,
        },
        ResolveError::Armin(err) => GitCoreError {
            code: "command_failed".to_string(),
            message: format!("failed to resolve repository path: {err}"),
        },
    }
}

fn map_git_ops_error(err: GitOpsError) -> GitCoreError {
    GitCoreError {
        code: "command_failed".to_string(),
        message: err.to_string(),
    }
}

fn map_stage_error(err: String) -> GitCoreError {
    GitCoreError {
        code: "command_failed".to_string(),
        message: err,
    }
}

fn git_core_error_response(id: &str, err: GitCoreError) -> Response {
    let code = match err.code.as_str() {
        "invalid_params" => error_codes::INVALID_PARAMS,
        "not_found" => error_codes::NOT_FOUND,
        "legacy_worktree_unsupported" => error_codes::INVALID_PARAMS,
        _ => error_codes::INTERNAL_ERROR,
    };
    Response::error_with_data(
        id,
        code,
        &err.message,
        serde_json::json!({
            "error_code": err.code,
        }),
    )
}
