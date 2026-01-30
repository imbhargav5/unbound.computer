//! Session handlers.

use crate::app::DaemonState;
use daemon_database::queries;
use daemon_ipc::{error_codes, Event, EventType, IpcServer, Method, Response};
use daemon_storage::SecretsManager;
use tracing::{debug, warn};

/// Register session handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_session_list(server, state.clone()).await;
    register_session_create(server, state.clone()).await;
    register_session_get(server, state.clone()).await;
    register_session_delete(server, state).await;
}

async fn register_session_list(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionList, move |req| {
            let db = state.db.clone();
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

                let result = tokio::task::spawn_blocking(move || {
                    let conn = db.get()?;
                    queries::list_sessions_for_repository(&conn, &repo_id)
                })
                .await
                .unwrap();

                match result {
                    Ok(sessions) => {
                        let session_data: Vec<serde_json::Value> = sessions
                            .iter()
                            .map(|s| {
                                serde_json::json!({
                                    "id": s.id,
                                    "repository_id": s.repository_id,
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
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}

async fn register_session_create(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionCreate, move |req| {
            let state = state.clone();
            async move {
                let repository_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("repository_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_lowercase());

                let title = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("title"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("New session")
                    .to_string();

                let Some(repository_id) = repository_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "repository_id is required",
                    );
                };

                // Generate session ID and secret upfront
                let session_id = uuid::Uuid::new_v4().to_string();
                let session_secret = SecretsManager::generate_session_secret();

                // Create session in database
                let db = state.db.clone();
                let session_id_clone = session_id.clone();
                let result = tokio::task::spawn_blocking(move || {
                    let conn = db.get()?;
                    let session = daemon_database::NewAgentCodingSession {
                        id: session_id_clone,
                        repository_id,
                        title,
                        claude_session_id: None,
                        is_worktree: false,
                        worktree_path: None,
                    };
                    queries::insert_session(&conn, &session)
                })
                .await
                .unwrap();

                let created_session = match result {
                    Ok(s) => s,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &e.to_string(),
                        )
                    }
                };

                // Cache the parsed secret key in memory
                if let Ok(key) = SecretsManager::parse_session_secret(&session_secret) {
                    state
                        .session_secret_cache
                        .insert(&created_session.id, key);
                }

                // Store session secret in both SQLite and Supabase simultaneously
                let sqlite_future = {
                    let state = state.clone();
                    let session_id = created_session.id.clone();
                    let session_secret = session_secret.clone();
                    async move {
                        if let Some(db_key) = *state.db_encryption_key.lock().unwrap() {
                            let nonce = daemon_database::generate_nonce();
                            match daemon_database::encrypt_content(
                                &db_key,
                                &nonce,
                                session_secret.as_bytes(),
                            ) {
                                Ok(encrypted) => {
                                    if let Ok(conn) = state.db.get() {
                                        if let Err(e) = queries::set_session_secret(
                                            &conn,
                                            &daemon_database::NewSessionSecret {
                                                session_id: session_id.clone(),
                                                encrypted_secret: encrypted,
                                                nonce: nonce.to_vec(),
                                            },
                                        ) {
                                            warn!(
                                                session_id = %session_id,
                                                "Failed to store session secret in SQLite: {}",
                                                e
                                            );
                                        } else {
                                            debug!(
                                                session_id = %session_id,
                                                "Stored session secret in SQLite"
                                            );
                                        }
                                    }
                                }
                                Err(e) => {
                                    warn!(
                                        session_id = %session_id,
                                        "Failed to encrypt session secret for SQLite: {}",
                                        e
                                    );
                                }
                            }
                        }
                    }
                };

                let supabase_future = {
                    let session_sync = state.session_sync.clone();
                    let session_id = created_session.id.clone();
                    let repository_id = created_session.repository_id.clone();
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

                // Run both storage operations concurrently
                tokio::join!(sqlite_future, supabase_future);

                // Broadcast SessionCreated event to all global subscribers
                let session_data = serde_json::json!({
                    "id": created_session.id,
                    "repository_id": created_session.repository_id,
                    "title": created_session.title,
                    "status": created_session.status.as_str(),
                    "is_worktree": created_session.is_worktree,
                    "worktree_path": created_session.worktree_path,
                    "created_at": created_session.created_at.to_rfc3339(),
                    "last_accessed_at": created_session.last_accessed_at.to_rfc3339(),
                });
                state.subscriptions.broadcast_global(Event::new(
                    EventType::SessionCreated,
                    &created_session.id,
                    session_data.clone(),
                    0,
                ));

                Response::success(&req.id, session_data)
            }
        })
        .await;
}

async fn register_session_get(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionGet, move |req| {
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
                    queries::get_session(&conn, &id)
                })
                .await
                .unwrap();

                match result {
                    Ok(Some(s)) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "session": {
                                "id": s.id,
                                "repository_id": s.repository_id,
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
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}

async fn register_session_delete(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SessionDelete, move |req| {
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
                    queries::delete_session(&conn, &id)
                })
                .await
                .unwrap();

                match result {
                    Ok(true) => {
                        Response::success(&req.id, serde_json::json!({ "deleted": true }))
                    }
                    Ok(false) => {
                        Response::error(&req.id, error_codes::NOT_FOUND, "Session not found")
                    }
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}
