//! Repository handlers.

use crate::app::DaemonState;
use armin::{NewRepository, RepositoryId, SessionReader, SessionWriter};
use daemon_ipc::{error_codes, IpcServer, Method, Response};

/// Register repository handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_repository_list(server, state.clone()).await;
    register_repository_add(server, state.clone()).await;
    register_repository_remove(server, state).await;
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
