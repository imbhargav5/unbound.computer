//! Repository handlers.

use crate::app::DaemonState;
use armin::{NewRepository, RepositoryId, SessionReader, SessionWriter};
use daemon_database::queries;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use gyomei::{FileRevision, GyomeiError};
use std::path::Path;
use tokio::task;
use yagami::{ListOptions, YagamiError};

/// Register repository handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_repository_list(server, state.clone()).await;
    register_repository_add(server, state.clone()).await;
    register_repository_remove(server, state.clone()).await;
    register_repository_list_files(server, state.clone()).await;
    register_repository_read_file(server, state.clone()).await;
    register_repository_read_file_slice(server, state.clone()).await;
    register_repository_write_file(server, state.clone()).await;
    register_repository_replace_file_range(server, state).await;
}

async fn register_repository_list(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryList, move |req| {
            let armin = state.armin.clone();
            async move {
                let repos = match armin.list_repositories() {
                    Ok(repos) => repos,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to list repositories: {}", e),
                        );
                    }
                };
                let repo_data: Vec<serde_json::Value> = repos
                    .iter()
                    .map(|r| {
                        serde_json::json!({
                            "id": r.id.as_str(),
                            "path": r.path,
                            "name": r.name,
                            "is_git_repository": r.is_git_repository,
                            "last_accessed_at": r.last_accessed_at.to_rfc3339(),
                        })
                    })
                    .collect();
                Response::success(&req.id, serde_json::json!({ "repositories": repo_data }))
            }
        })
        .await;
}

async fn register_repository_add(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryAdd, move |req| {
            let armin = state.armin.clone();
            async move {
                let path = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("path"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let name = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("name"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let is_git = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("is_git_repository"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);

                let (Some(path), Some(name)) = (path, name) else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "path and name are required",
                    );
                };

                let repo = NewRepository {
                    id: RepositoryId::new(),
                    path,
                    name,
                    is_git_repository: is_git,
                    sessions_path: None,
                    default_branch: None,
                    default_remote: None,
                };

                let created = match armin.create_repository(repo) {
                    Ok(r) => r,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to create repository: {}", e),
                        );
                    }
                };

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "id": created.id.as_str(),
                        "path": created.path,
                        "name": created.name,
                        "is_git_repository": created.is_git_repository,
                    }),
                )
            }
        })
        .await;
}

async fn register_repository_remove(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryRemove, move |req| {
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

                let repo_id = RepositoryId::from_string(&id);
                let deleted = match armin.delete_repository(&repo_id) {
                    Ok(d) => d,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to delete repository: {}", e),
                        );
                    }
                };

                if deleted {
                    Response::success(&req.id, serde_json::json!({ "deleted": true }))
                } else {
                    Response::error(&req.id, error_codes::NOT_FOUND, "Repository not found")
                }
            }
        })
        .await;
}

async fn register_repository_list_files(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryListFiles, move |req| {
            let state = state.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str());

                let Some(session_id) = session_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id is required",
                    );
                };

                let relative_path = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("relative_path"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                let include_hidden = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("include_hidden"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);

                let root_path = match resolve_session_root(&state, session_id).await {
                    Ok(root) => root,
                    Err((code, message)) => return Response::error(&req.id, code, &message),
                };

                let options = ListOptions {
                    include_hidden,
                    ..Default::default()
                };

                let entries = match yagami::list_dir(Path::new(&root_path), relative_path, options)
                {
                    Ok(entries) => entries,
                    Err(err) => {
                        let (code, message) = map_yagami_error(err);
                        return Response::error(&req.id, code, &message);
                    }
                };

                let entries_json: Vec<serde_json::Value> = entries
                    .into_iter()
                    .map(|entry| {
                        serde_json::json!({
                            "name": entry.name,
                            "path": entry.path,
                            "is_dir": entry.is_dir,
                            "has_children": entry.has_children,
                        })
                    })
                    .collect();

                Response::success(&req.id, serde_json::json!({ "entries": entries_json }))
            }
        })
        .await;
}

async fn register_repository_read_file(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryReadFile, move |req| {
            let state = state.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str());

                let Some(session_id) = session_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id is required",
                    );
                };

                let relative_path = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("relative_path"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                if let Some(response) = validate_relative_path_params(&req.id, relative_path) {
                    return response;
                }

                let max_bytes = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("max_bytes"))
                    .and_then(|v| v.as_u64())
                    .filter(|v| *v > 0)
                    .unwrap_or(4 * 1024 * 1024);

                let root_path = match resolve_session_root(&state, session_id).await {
                    Ok(root) => root,
                    Err((code, message)) => return Response::error(&req.id, code, &message),
                };

                let gyomei = state.gyomei.clone();
                let relative_path = relative_path.to_string();
                let root_path_for_task = root_path.clone();
                let read_result = task::spawn_blocking(move || {
                    gyomei.read_full(
                        Path::new(&root_path_for_task),
                        &relative_path,
                        max_bytes as usize,
                    )
                })
                .await;

                let result = match read_result {
                    Ok(Ok(result)) => result,
                    Ok(Err(err)) => return map_gyomei_error(&req.id, err),
                    Err(err) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("read task failed: {}", err),
                        );
                    }
                };

                let mut payload = serde_json::json!({
                    "content": result.content,
                    "is_truncated": result.is_truncated,
                    "revision": result.revision,
                    "total_lines": result.total_lines,
                });

                if let Some(reason) = result.read_only_reason {
                    payload["read_only_reason"] = serde_json::json!(reason);
                }

                Response::success(&req.id, payload)
            }
        })
        .await;
}

async fn register_repository_read_file_slice(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryReadFileSlice, move |req| {
            let state = state.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str());

                let Some(session_id) = session_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id is required",
                    );
                };

                let relative_path = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("relative_path"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                if let Some(response) = validate_relative_path_params(&req.id, relative_path) {
                    return response;
                }

                let start_line = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("start_line"))
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0) as usize;

                let end_line_exclusive = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("end_line_exclusive"))
                    .and_then(|v| v.as_u64())
                    .map(|v| v as usize)
                    .unwrap_or_else(|| start_line.saturating_add(200));

                if end_line_exclusive < start_line {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "end_line_exclusive must be >= start_line",
                    );
                }

                let line_count = end_line_exclusive.saturating_sub(start_line);
                let max_bytes = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("max_bytes"))
                    .and_then(|v| v.as_u64())
                    .filter(|v| *v > 0)
                    .unwrap_or(1_000_000);

                let root_path = match resolve_session_root(&state, session_id).await {
                    Ok(root) => root,
                    Err((code, message)) => return Response::error(&req.id, code, &message),
                };

                let gyomei = state.gyomei.clone();
                let relative_path = relative_path.to_string();
                let root_path_for_task = root_path.clone();
                let slice_result = task::spawn_blocking(move || {
                    gyomei.read_slice(
                        Path::new(&root_path_for_task),
                        &relative_path,
                        start_line,
                        line_count,
                        max_bytes as usize,
                    )
                })
                .await;

                let result = match slice_result {
                    Ok(Ok(result)) => result,
                    Ok(Err(err)) => return map_gyomei_error(&req.id, err),
                    Err(err) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("read slice task failed: {}", err),
                        );
                    }
                };

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "content": result.content,
                        "start_line": result.start_line,
                        "end_line_exclusive": result.end_line_exclusive,
                        "total_lines": result.total_lines,
                        "has_more_before": result.has_more_before,
                        "has_more_after": result.has_more_after,
                        "is_truncated": result.is_truncated,
                        "revision": result.revision,
                    }),
                )
            }
        })
        .await;
}

async fn register_repository_write_file(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryWriteFile, move |req| {
            let state = state.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str());
                let Some(session_id) = session_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id is required",
                    );
                };

                let relative_path = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("relative_path"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                if let Some(response) = validate_relative_path_params(&req.id, relative_path) {
                    return response;
                }

                let content = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("content"))
                    .and_then(|v| v.as_str());
                let Some(content) = content else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "content is required",
                    );
                };

                let force = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("force"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);

                let expected_revision = match parse_expected_revision(req.params.as_ref()) {
                    Ok(revision) => revision,
                    Err(message) => {
                        return Response::error(&req.id, error_codes::INVALID_PARAMS, &message);
                    }
                };

                let root_path = match resolve_session_root(&state, session_id).await {
                    Ok(root) => root,
                    Err((code, message)) => return Response::error(&req.id, code, &message),
                };

                let gyomei = state.gyomei.clone();
                let relative_path = relative_path.to_string();
                let content = content.to_string();
                let root_path_for_task = root_path.clone();
                let write_result = task::spawn_blocking(move || {
                    gyomei.write_full(
                        Path::new(&root_path_for_task),
                        &relative_path,
                        &content,
                        expected_revision.as_ref(),
                        force,
                    )
                })
                .await;

                match write_result {
                    Ok(Ok(result)) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "revision": result.revision,
                            "bytes_written": result.bytes_written,
                            "total_lines": result.total_lines,
                        }),
                    ),
                    Ok(Err(err)) => map_gyomei_error(&req.id, err),
                    Err(err) => Response::error(
                        &req.id,
                        error_codes::INTERNAL_ERROR,
                        &format!("write task failed: {}", err),
                    ),
                }
            }
        })
        .await;
}

async fn register_repository_replace_file_range(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryReplaceFileRange, move |req| {
            let state = state.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str());
                let Some(session_id) = session_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id is required",
                    );
                };

                let relative_path = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("relative_path"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                if let Some(response) = validate_relative_path_params(&req.id, relative_path) {
                    return response;
                }

                let start_line = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("start_line"))
                    .and_then(|v| v.as_u64());
                let Some(start_line) = start_line else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "start_line is required",
                    );
                };

                let end_line_exclusive = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("end_line_exclusive"))
                    .and_then(|v| v.as_u64());
                let Some(end_line_exclusive) = end_line_exclusive else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "end_line_exclusive is required",
                    );
                };

                let replacement = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("replacement"))
                    .and_then(|v| v.as_str());
                let Some(replacement) = replacement else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "replacement is required",
                    );
                };

                let force = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("force"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);

                let expected_revision = match parse_expected_revision(req.params.as_ref()) {
                    Ok(revision) => revision,
                    Err(message) => {
                        return Response::error(&req.id, error_codes::INVALID_PARAMS, &message);
                    }
                };

                let root_path = match resolve_session_root(&state, session_id).await {
                    Ok(root) => root,
                    Err((code, message)) => return Response::error(&req.id, code, &message),
                };

                let gyomei = state.gyomei.clone();
                let relative_path = relative_path.to_string();
                let replacement = replacement.to_string();
                let root_path_for_task = root_path.clone();
                let replace_result = task::spawn_blocking(move || {
                    gyomei.replace_range(
                        Path::new(&root_path_for_task),
                        &relative_path,
                        start_line as usize,
                        end_line_exclusive as usize,
                        &replacement,
                        expected_revision.as_ref(),
                        force,
                    )
                })
                .await;

                match replace_result {
                    Ok(Ok(result)) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "revision": result.revision,
                            "bytes_written": result.bytes_written,
                            "total_lines": result.total_lines,
                        }),
                    ),
                    Ok(Err(err)) => map_gyomei_error(&req.id, err),
                    Err(err) => Response::error(
                        &req.id,
                        error_codes::INTERNAL_ERROR,
                        &format!("replace range task failed: {}", err),
                    ),
                }
            }
        })
        .await;
}

async fn resolve_session_root(
    state: &DaemonState,
    session_id: &str,
) -> Result<String, (i32, String)> {
    let session_id_owned = session_id.to_string();
    let result = state
        .db
        .call(move |conn| {
            let session = queries::get_session(conn, &session_id_owned)?.ok_or_else(|| {
                daemon_database::DatabaseError::NotFound("Session not found".to_string())
            })?;
            let repo = queries::get_repository(conn, &session.repository_id)?.ok_or_else(|| {
                daemon_database::DatabaseError::NotFound("Repository not found".to_string())
            })?;
            let root_path = if session.is_worktree {
                session.worktree_path.unwrap_or(repo.path)
            } else {
                repo.path
            };
            Ok(root_path)
        })
        .await;

    match result {
        Ok(path) => Ok(path),
        Err(daemon_database::DatabaseError::NotFound(msg)) => Err((error_codes::NOT_FOUND, msg)),
        Err(e) => Err((error_codes::INTERNAL_ERROR, e.to_string())),
    }
}

fn validate_relative_path_params(id: &str, relative_path: &str) -> Option<Response> {
    if relative_path.is_empty() {
        return Some(Response::error(
            id,
            error_codes::INVALID_PARAMS,
            "relative_path is required",
        ));
    }
    if Path::new(relative_path).is_absolute() {
        return Some(Response::error(
            id,
            error_codes::INVALID_PARAMS,
            "relative_path must be relative",
        ));
    }
    None
}

fn parse_expected_revision(
    params: Option<&serde_json::Value>,
) -> Result<Option<FileRevision>, String> {
    let Some(params) = params else {
        return Ok(None);
    };

    let Some(value) = params.get("expected_revision") else {
        return Ok(None);
    };

    serde_json::from_value::<FileRevision>(value.clone())
        .map(Some)
        .map_err(|err| format!("invalid expected_revision: {}", err))
}

fn map_gyomei_error(id: &str, err: GyomeiError) -> Response {
    let message = err.to_string();
    match err {
        GyomeiError::InvalidRoot | GyomeiError::NotFound => {
            Response::error(id, error_codes::NOT_FOUND, &message)
        }
        GyomeiError::InvalidRelativePath
        | GyomeiError::PathTraversal
        | GyomeiError::NotAFile
        | GyomeiError::InvalidUtf8
        | GyomeiError::MissingExpectedRevision
        | GyomeiError::InvalidRange => Response::error(id, error_codes::INVALID_PARAMS, &message),
        GyomeiError::RevisionConflict { current_revision } => Response::error_with_data(
            id,
            error_codes::CONFLICT,
            "revision conflict",
            serde_json::json!({ "current_revision": current_revision }),
        ),
        GyomeiError::Io(_) => Response::error(id, error_codes::INTERNAL_ERROR, &message),
    }
}

fn map_yagami_error(err: YagamiError) -> (i32, String) {
    match err {
        YagamiError::InvalidRoot => (error_codes::NOT_FOUND, err.to_string()),
        YagamiError::InvalidRelativePath | YagamiError::PathTraversal => {
            (error_codes::INVALID_PARAMS, err.to_string())
        }
        YagamiError::NotADirectory => (error_codes::INVALID_PARAMS, err.to_string()),
        YagamiError::Io(_) => (error_codes::INTERNAL_ERROR, err.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_expected_revision_accepts_valid_payload() {
        let params = serde_json::json!({
            "expected_revision": {
                "token": "abc",
                "len_bytes": 42,
                "modified_unix_ns": 1000
            }
        });

        let parsed = parse_expected_revision(Some(&params)).expect("expected revision");
        assert_eq!(
            parsed,
            Some(FileRevision {
                token: "abc".to_string(),
                len_bytes: 42,
                modified_unix_ns: 1000,
            })
        );
    }

    #[test]
    fn parse_expected_revision_rejects_invalid_payload() {
        let params = serde_json::json!({
            "expected_revision": "oops"
        });

        let err = parse_expected_revision(Some(&params)).expect_err("invalid revision");
        assert!(err.contains("invalid expected_revision"));
    }

    #[test]
    fn map_gyomei_conflict_to_conflict_response() {
        let revision = FileRevision {
            token: "conflict-token".to_string(),
            len_bytes: 12,
            modified_unix_ns: 345,
        };

        let response = map_gyomei_error(
            "req-1",
            GyomeiError::RevisionConflict {
                current_revision: revision.clone(),
            },
        );

        let error = response.error.expect("error response");
        assert_eq!(error.code, error_codes::CONFLICT);
        assert_eq!(error.message, "revision conflict");
        let data = error.data.expect("conflict data");
        assert_eq!(
            data["current_revision"]["token"].as_str(),
            Some("conflict-token")
        );
    }
}
