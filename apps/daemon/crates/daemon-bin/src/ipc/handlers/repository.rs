//! Repository handlers.

use crate::app::DaemonState;
use daemon_database::queries;
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
            let db = state.db.clone();
            async move {
                let result = tokio::task::spawn_blocking(move || {
                    let conn = db.get()?;
                    queries::list_repositories(&conn)
                })
                .await
                .unwrap();

                match result {
                    Ok(repos) => {
                        let repo_data: Vec<serde_json::Value> = repos
                            .iter()
                            .map(|r| {
                                serde_json::json!({
                                    "id": r.id,
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
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}

async fn register_repository_add(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryAdd, move |req| {
            let db = state.db.clone();
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

                let result = tokio::task::spawn_blocking(move || {
                    let conn = db.get()?;
                    let repo = daemon_database::NewRepository {
                        id: uuid::Uuid::new_v4().to_string(),
                        path,
                        name,
                        is_git_repository: is_git,
                        sessions_path: None,
                        default_branch: None,
                        default_remote: None,
                    };
                    queries::insert_repository(&conn, &repo)
                })
                .await
                .unwrap();

                match result {
                    Ok(r) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "id": r.id,
                            "path": r.path,
                            "name": r.name,
                            "is_git_repository": r.is_git_repository,
                        }),
                    ),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}

async fn register_repository_remove(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::RepositoryRemove, move |req| {
            let db = state.db.clone();
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

                let result = tokio::task::spawn_blocking(move || {
                    let conn = db.get()?;
                    queries::delete_repository(&conn, &id)
                })
                .await
                .unwrap();

                match result {
                    Ok(true) => {
                        Response::success(&req.id, serde_json::json!({ "deleted": true }))
                    }
                    Ok(false) => {
                        Response::error(&req.id, error_codes::NOT_FOUND, "Repository not found")
                    }
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}
