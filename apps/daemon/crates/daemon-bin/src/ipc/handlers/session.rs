//! Session handlers.

use crate::app::DaemonState;
use armin::{NewSession, RepositoryId, SessionId, SessionReader, SessionWriter};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use daemon_storage::SecretsManager;
use piccolo::{create_worktree, remove_worktree};
use std::path::Path;
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

                // Worktree params
                let is_worktree = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("is_worktree"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);

                let worktree_name = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("worktree_name"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let branch_name = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("branch_name"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let Some(repository_id) = repository_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "repository_id is required",
                    );
                };

                // Generate session ID and secret upfront
                let session_id = SessionId::new();
                let session_secret = SecretsManager::generate_session_secret();

                // Determine worktree path if creating a worktree
                let worktree_path = if is_worktree {
                    // Get repository from Armin
                    let repo_id = RepositoryId::from_string(&repository_id);
                    let repo = match state.armin.get_repository(&repo_id) {
                        Ok(Some(r)) => r,
                        Ok(None) => {
                            return Response::error(
                                &req.id,
                                error_codes::NOT_FOUND,
                                "Repository not found",
                            );
                        }
                        Err(e) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &format!("Failed to get repository: {}", e),
                            );
                        }
                    };

                    // Use session ID as worktree name if not provided
                    let wt_name = worktree_name.as_deref().unwrap_or(session_id.as_str());

                    // Create the git worktree
                    match create_worktree(
                        Path::new(&repo.path),
                        wt_name,
                        branch_name.as_deref(),
                    ) {
                        Ok(path) => Some(path),
                        Err(e) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &format!("Failed to create worktree: {}", e),
                            );
                        }
                    }
                } else {
                    None
                };

                // Create session via Armin (single source of truth)
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
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to create session: {}", e),
                        );
                    }
                };

                // Cache the parsed secret key in memory
                if let Ok(key) = SecretsManager::parse_session_secret(&session_secret) {
                    state
                        .session_secret_cache
                        .insert(created_session.id.as_str(), key);
                }

                // Store session secret via Armin and sync to Supabase
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
                                    // Store via Armin
                                    let secret = armin::NewSessionSecret {
                                        session_id: session_id.clone(),
                                        encrypted_secret: encrypted,
                                        nonce: nonce.to_vec(),
                                    };
                                    if let Err(e) = state.armin.set_session_secret(secret) {
                                        warn!(
                                            session_id = %session_id.as_str(),
                                            "Failed to store session secret: {}",
                                            e
                                        );
                                    }
                                    debug!(
                                        session_id = %session_id.as_str(),
                                        "Stored session secret via Armin"
                                    );
                                }
                                Err(e) => {
                                    warn!(
                                        session_id = %session_id.as_str(),
                                        "Failed to encrypt session secret: {}",
                                        e
                                    );
                                }
                            }
                        }
                    }
                };

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

                // Run both storage operations concurrently
                tokio::join!(sqlite_future, supabase_future);

                // Note: SessionCreated side-effect is emitted by Armin.
                // Clients receive it via the subscription manager.
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

                Response::success(&req.id, session_data)
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
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "id is required",
                    );
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
                    Err(e) => {
                        Response::error(&req.id, error_codes::INTERNAL_ERROR, &format!("Failed to get session: {}", e))
                    }
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
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "id is required",
                    );
                };

                // First, get the session to check if it's a worktree
                let session_id = SessionId::from_string(&id);
                let session = match state.armin.get_session(&session_id) {
                    Ok(Some(s)) => s,
                    Ok(None) => {
                        return Response::error(&req.id, error_codes::NOT_FOUND, "Session not found");
                    }
                    Err(e) => {
                        return Response::error(&req.id, error_codes::INTERNAL_ERROR, &format!("Failed to get session: {}", e));
                    }
                };

                // If it's a worktree session, clean up the worktree
                if session.is_worktree {
                    if let Some(worktree_path) = &session.worktree_path {
                        // Get repository path for worktree cleanup
                        if let Ok(Some(repo)) = state.armin.get_repository(&session.repository_id) {
                            // Try to remove the worktree, but don't fail the deletion if this fails
                            if let Err(e) = remove_worktree(
                                Path::new(&repo.path),
                                Path::new(worktree_path),
                            ) {
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
                        return Response::error(&req.id, error_codes::INTERNAL_ERROR, &format!("Failed to delete session: {}", e));
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
