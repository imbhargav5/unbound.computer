//! Repository handlers.

use crate::app::DaemonState;
use armin::{NewRepository, RepositoryId, SessionReader, SessionWriter};
use daemon_database::queries;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use std::path::Path;
use yagami::{ListOptions, YagamiError};

/// Register repository handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_repository_list(server, state.clone()).await;
    register_repository_add(server, state.clone()).await;
    register_repository_remove(server, state.clone()).await;
    register_repository_list_files(server, state).await;
}

async fn register_repository_list(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryList, move |req| {
            let armin = state.armin.clone();
            async move {
                let repos = armin.list_repositories();
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
                Response::success(
                    &req.id,
                    serde_json::json!({ "repositories": repo_data }),
                )
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

                let created = armin.create_repository(repo);

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
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "id is required",
                    );
                };

                let repo_id = RepositoryId::from_string(&id);
                let deleted = armin.delete_repository(&repo_id);

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

                let root_path = match resolve_session_root(&state, session_id) {
                    Ok(root) => root,
                    Err((code, message)) => return Response::error(&req.id, code, &message),
                };

                let options = ListOptions {
                    include_hidden,
                    ..Default::default()
                };

                let entries = match yagami::list_dir(Path::new(&root_path), relative_path, options) {
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

fn resolve_session_root(state: &DaemonState, session_id: &str) -> Result<String, (i32, String)> {
    let conn = state
        .db
        .get()
        .map_err(|e| (error_codes::INTERNAL_ERROR, e.to_string()))?;

    let session = queries::get_session(&conn, session_id)
        .map_err(|e| (error_codes::INTERNAL_ERROR, e.to_string()))?;

    let Some(session) = session else {
        return Err((error_codes::NOT_FOUND, "Session not found".to_string()));
    };

    let repo = queries::get_repository(&conn, &session.repository_id)
        .map_err(|e| (error_codes::INTERNAL_ERROR, e.to_string()))?;

    let Some(repo) = repo else {
        return Err((error_codes::NOT_FOUND, "Repository not found".to_string()));
    };

    let root_path = if session.is_worktree {
        session.worktree_path.unwrap_or(repo.path)
    } else {
        repo.path
    };

    Ok(root_path)
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
