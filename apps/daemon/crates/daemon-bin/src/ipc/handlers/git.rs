//! Git handlers.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use piccolo::{
    commit, discard_changes, get_branches, get_file_diff, get_log, get_status, push, stage_files,
    unstage_files,
};
use sakura_working_dir_resolution::{resolve_repository_path, ResolveError};

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
    if let Some(repo_id) = params
        .as_ref()
        .and_then(|p| p.get("repository_id"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_lowercase())
    {
        resolve_repository_path(&*state.armin, &repo_id).map_err(map_resolve_error)
    } else if let Some(path) = params
        .as_ref()
        .and_then(|p| p.get("path"))
        .and_then(|v| v.as_str())
    {
        Ok(path.to_string())
    } else {
        Err((
            error_codes::INVALID_PARAMS,
            "repository_id or path is required".to_string(),
        ))
    }
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
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                let message = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("message"))
                    .and_then(|v| v.as_str());

                let Some(message) = message else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "message is required",
                    );
                };

                let author_name = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("author_name"))
                    .and_then(|v| v.as_str());

                let author_email = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("author_email"))
                    .and_then(|v| v.as_str());

                match commit(
                    std::path::Path::new(&repo_path),
                    message,
                    author_name,
                    author_email,
                ) {
                    Ok(result) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "oid": result.oid,
                            "short_oid": result.short_oid,
                            "summary": result.summary,
                        }),
                    ),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
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
                let repo_path = match extract_repo_path(&state, &req.params).await {
                    Ok(p) => p,
                    Err((code, msg)) => return Response::error(&req.id, code, &msg),
                };

                let remote = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("remote"))
                    .and_then(|v| v.as_str());

                let branch = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("branch"))
                    .and_then(|v| v.as_str());

                match push(std::path::Path::new(&repo_path), remote, branch) {
                    Ok(result) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "remote": result.remote,
                            "branch": result.branch,
                            "success": result.success,
                        }),
                    ),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}
