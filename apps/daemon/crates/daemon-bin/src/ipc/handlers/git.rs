//! Git handlers.

use crate::app::DaemonState;
use daemon_core::{get_file_diff, get_status};
use daemon_database::queries;
use daemon_ipc::{error_codes, IpcServer, Method, Response};

/// Register git handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_git_status(server, state.clone()).await;
    register_git_diff_file(server, state).await;
}

async fn register_git_status(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GitStatus, move |req| {
            let state = state.clone();
            async move {
                // Get repository path from params (either by ID or direct path)
                let repo_path = if let Some(repo_id) = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("repository_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_lowercase())
                {
                    // Look up repository path from database
                    let conn = match state.db.get() {
                        Ok(c) => c,
                        Err(e) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &e.to_string(),
                            )
                        }
                    };
                    match queries::get_repository(&conn, &repo_id) {
                        Ok(Some(repo)) => repo.path,
                        Ok(None) => {
                            return Response::error(
                                &req.id,
                                error_codes::NOT_FOUND,
                                "Repository not found",
                            )
                        }
                        Err(e) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &e.to_string(),
                            )
                        }
                    }
                } else if let Some(path) = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("path"))
                    .and_then(|v| v.as_str())
                {
                    path.to_string()
                } else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "repository_id or path is required",
                    );
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
                // Get repository path
                let repo_path = if let Some(repo_id) = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("repository_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_lowercase())
                {
                    let conn = match state.db.get() {
                        Ok(c) => c,
                        Err(e) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &e.to_string(),
                            )
                        }
                    };
                    match queries::get_repository(&conn, &repo_id) {
                        Ok(Some(repo)) => repo.path,
                        Ok(None) => {
                            return Response::error(
                                &req.id,
                                error_codes::NOT_FOUND,
                                "Repository not found",
                            )
                        }
                        Err(e) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &e.to_string(),
                            )
                        }
                    }
                } else if let Some(path) = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("path"))
                    .and_then(|v| v.as_str())
                {
                    path.to_string()
                } else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "repository_id or path is required",
                    );
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
