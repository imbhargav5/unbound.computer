//! Authentication status handler.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};

/// Register the auth status handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthStatus, move |req| {
            let secrets = state.secrets.clone();
            async move {
                let result = tokio::task::spawn_blocking(move || {
                    let secrets = secrets.lock().unwrap();
                    match secrets.has_supabase_session() {
                        Ok(true) => {
                            let meta = secrets.get_supabase_session_meta().ok().flatten();
                            Ok(serde_json::json!({
                                "logged_in": true,
                                "authenticated": true,
                                "user_id": meta.as_ref().map(|m| &m.user_id),
                                "email": meta.as_ref().and_then(|m| m.email.as_ref()),
                                "expires_at": meta.as_ref().map(|m| &m.expires_at),
                            }))
                        }
                        Ok(false) => Ok(serde_json::json!({
                            "logged_in": false,
                            "authenticated": false
                        })),
                        Err(e) => Err(e.to_string()),
                    }
                })
                .await
                .unwrap();

                match result {
                    Ok(data) => Response::success(&req.id, data),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e),
                }
            }
        })
        .await;
}
